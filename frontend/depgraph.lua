--[[--
DepGraph module.
Library for constructing dependency graphs.

Example:

    local dg = DepGraph:new{}
    dg:addNode('a1', {'a2', 'b1'})
    dg:addNode('b1', {'a2', 'c1'})
    dg:addNode('c1')
    -- The return value of dg:serialize() will be:
    -- {'a2', 'c1', 'b1', 'a1'}

NOTE: Insertion order is preserved, duplicates are automatically prevented (both as main nodes and as deps).

]]

local DepGraph = {}

function DepGraph:new(new_o)
    local o = new_o or {}
    o.nodes = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Check if node exists, and is active
function DepGraph:checkNode(id)
    for _, n in ipairs(self.nodes) do
       if n.key == id and not n.disabled then
           return true
       end
    end

    return false
end

-- Returns a (node, node_index) tuple
function DepGraph:getNode(id)
    for i, n in ipairs(self.nodes) do
        if n.key == id then
            return n, i
        end
    end

    return nil, nil
end

-- Like getNode, but only for active nodes:
-- if node is nil but index is set, node is disabled
function DepGraph:getActiveNode(id)
    local node, index = self:getNode(id)
    if node and node.disabled then
        return nil, index
    end

    return node, index
end

-- Add a node, with an optional list of dependencies
-- If dependencies don't exist as proper nodes yet, they'll be created, in order.
-- If node already exists, the new list of dependencies is *appended* to the existing one, without duplicates.
function DepGraph:addNode(node_key, deps)
    -- Find main node if it already exists
    local node = self:getNode(node_key)

    if node then
        -- If it exists, but was disabled, re-enable it
        if node.disabled then
           node.disabled = nil
        end
    else
        -- If it doesn't exist at all, create it
        node = { key = node_key }
        table.insert(self.nodes, node)
    end

    -- No dependencies? We're done!
    if not deps then
        return
    end

    -- Create dep nodes if they don't already exist
    local node_deps = node.deps or {}
    for _, dep_node_key in ipairs(deps) do
        local dep_node = self:getNode(dep_node_key)

        if dep_node then
            -- If it exists, but was disabled, re-enable it
            if dep_node.disabled then
                dep_node.disabled = nil
            end
        else
            -- Create dep node itself if need be
            dep_node = { key = dep_node_key }
            table.insert(self.nodes, dep_node)
        end

        -- Update deps array the long way 'round, and prevent duplicates, in case deps was funky as hell.
        local exists = false
        for _, k in ipairs(node_deps) do
            if k == dep_node_key then
                exists = true
                break
            end
        end
        if not exists then
            table.insert(node_deps, dep_node_key)
        end
    end
    -- Update main node with its updated deps
    node.deps = node_deps
end

-- Attempt to remove a node, as well as all traces of it from other nodes' deps
-- If node has deps, it's kept, but marked as disabled, c.f., lengthy comment below.
function DepGraph:removeNode(node_key)
    -- We shouldn't remove a node if it has dependencies (as these may have been added via addNodeDep
    -- (as opposed to the optional deps list passed to addNode), like what InputContainer does with overrides,
    -- overrides originating from completely *different* nodes,
    -- meaning those other nodes basically add themselves to another's deps).
    -- We don't want to lose the non-native dependency on these other nodes in case we later re-addNode this one
    -- with its stock dependency list.
    local node, index = self:getNode(node_key)
    if node then
        if not node.deps or #node.deps == 0 then
            -- No dependencies, can be wiped safely
            table.remove(self.nodes, index)
        else
            -- Can't remove it, just flag it as disabled instead
            node.disabled = true
        end
    end
    -- On the other hand, we definitely should remove it from the deps of every *other* node.
    for _, curr_node in ipairs(self.nodes) do
        -- Is not the to be removed node, and has deps
        if curr_node.key ~= node_key and curr_node.deps then
            -- Walk that node's deps to check if it depends on us
            for idx, dep_node_key in ipairs(curr_node.deps) do
                -- If it did, wipe ourselves from there
                if dep_node_key == node_key then
                    table.remove(curr_node.deps, idx)
                    break
                end
            end
        end
    end
end

-- Add a single dep_node_key to node_key's deps
function DepGraph:addNodeDep(node_key, dep_node_key)
    -- Check the main node
    local node = self:getNode(node_key)

    if node then
        -- If it exists, but was disabled, re-enable it
        if node.disabled then
           node.disabled = nil
        end
    else
        -- If it doesn't exist at all, create it
        node = { key = node_key }
        table.insert(self.nodes, node)
    end

    -- Then check the dep node
    local dep_node = self:getNode(dep_node_key)

    if dep_node then
        -- If it exists, but was disabled, re-enable it
        if dep_node.disabled then
            dep_node.disabled = nil
        end
    else
        -- Create dep node itself if need be
        dep_node = { key = dep_node_key }
        table.insert(self.nodes, dep_node)
    end

    -- If main node currently doesn't have deps, start with an empty array
    if not node.deps then
        node.deps = {}
    end

    -- Prevent duplicate deps
    local exists = false
    for _, k in ipairs(node.deps) do
        if k == dep_node_key then
            exists = true
            break
        end
    end
    if not exists then
        table.insert(node.deps, dep_node_key)
    end
end

-- Remove a single dep_node_key from node_key's deps
function DepGraph:removeNodeDep(node_key, dep_node_key)
    local node = self:getNode(node_key)
    if node.deps then
        for idx, dep_key in ipairs(node.deps) do
            if dep_key == dep_node_key then
                table.remove(node.deps, idx)
                break
            end
        end
    end
end

-- Return a list (array) of node keys, ordered by insertion order and dependency.
-- Dependencies come first (and are also ordered by insertion order themselves).
function DepGraph:serialize()
    local visited = {}
    local ordered_nodes = {}

    for _, n in ipairs(self.nodes) do
        local node_key = n.key
        if not visited[node_key] then
            local queue = { node_key }
            while #queue > 0 do
                local pos = #queue
                local curr_node_key = queue[pos]
                local curr_node = self:getActiveNode(curr_node_key)
                local all_deps_visited = true
                if curr_node and curr_node.deps then
                    for _, dep_node_key in ipairs(curr_node.deps) do
                        if not visited[dep_node_key] then
                            -- Only insert to queue for later process if node has dependencies
                            local dep_node = self:getActiveNode(dep_node_key)
                            -- Only if it was active!
                            if dep_node then
                                if dep_node.deps then
                                    table.insert(queue, dep_node_key)
                                else
                                    table.insert(ordered_nodes, dep_node_key)
                                end
                            end
                            visited[dep_node_key] = true
                            all_deps_visited = false
                            break
                        end
                    end
                end
                if all_deps_visited then
                    visited[curr_node_key] = true
                    table.remove(queue, pos)
                    -- Only if it was active!
                    if curr_node then
                        table.insert(ordered_nodes, curr_node_key)
                    end
                end
            end
        end
    end
    return ordered_nodes
end

return DepGraph
