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

function DepGraph:checkNode(id)
    for i, _ in ipairs(self.nodes) do
       if self.nodes[i].key == id then
           return true
       end
    end

    return false
end

function DepGraph:getNode(id)
    local node = nil
    local index = nil
    for i, _ in ipairs(self.nodes) do
       if self.nodes[i].key == id then
           node = self.nodes[i]
           index = i
           break
       end
    end
    return node, index
end

function DepGraph:addNode(node_key, deps)
    -- Find main node if it already exists
    local node = self:getNode(node_key)

    -- Create it otherwise
    if not node then
        node = { key = node_key }
        table.insert(self.nodes, node)
    end

    if not deps then return end

    -- Create dep nodes if they don't already exist
    local node_deps = {}
    for _, dep_node_key in ipairs(deps) do
        local dep_node = self:getNode(dep_node_key)

        -- Create dep node itself if need be
        if not dep_node then
            dep_node = { key = dep_node_key }
            table.insert(self.nodes, dep_node)
        end

        -- Build deps array the ling way 'round, and prevent duplicates, in case deps was funky as hell.
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
    -- Update main node with its deps
    node.deps = node_deps
end

function DepGraph:removeNode(node_key)
    -- We should not remove it from self.nodes if it has
    -- a .deps array (it is the other nodes, that had this
    -- one in their override=, that have added themselves in
    -- this node's .deps). We don't want to lose these
    -- dependencies if we later re-addNode this node.
    local node, index = self:getNode(node_key)
    if node then
        if not node.deps or #node.deps == 0 then
            -- We need to clear *all* references to that node for it to be GC'ed...
            node = nil
            table.remove(self.nodes, index)
        end
    end
    -- But we should remove it from the .deps of *other* nodes.
    for i, _ in ipairs(self.nodes) do
        local curr_node = self.nodes[i]
        -- Is not the to be removed node, and has deps
        if curr_node.key ~= node_key and curr_node.deps then
            -- Walk that node's deps to check if it depends on us
            for idx, dep_node_key in ipairs(curr_node.deps) do
                -- If it did, wipe ourselves from there
                if dep_node_key == node_key then
                    -- Wipe all refs
                    curr_node.deps[idx] = nil
                    table.remove(self.nodes[i].deps, idx)
                    break
                end
            end
        end
    end
end

-- Add dep_node_key to node_key's deps
function DepGraph:addNodeDep(node_key, dep_node_key)
    local node = self:getNode(node_key)

    if not node then
        node = { key = node_key }
        table.insert(self.nodes, node)
    end

    -- We'll need a table ;)
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

function DepGraph:removeNodeDep(node_key, dep_node_key)
    local node, index = self:getNode(node_key)
    if node.deps then
        for idx, dep_key in ipairs(node.deps) do
            if dep_key == dep_node_key then
                node.deps[idx] = nil
                table.remove(self.nodes[index].deps, idx)
                break
            end
        end
    end
end

function DepGraph:serialize()
    local visited = {}
    local ordered_nodes = {}

    for i, _ in ipairs(self.nodes) do
        local node_key = self.nodes[i].key
        if not visited[node_key] then
            local queue = { node_key }
            while #queue > 0 do
                local pos = #queue
                local curr_node_key = queue[pos]
                local curr_node = self:getNode(curr_node_key)
                local all_deps_visited = true
                if curr_node.deps then
                    for _, dep_node_key in ipairs(curr_node.deps) do
                        if not visited[dep_node_key] then
                            -- only insert to queue for later process if node has dependencies
                            local dep_node = self:getNode(dep_node_key)
                            if dep_node and dep_node.deps then
                                table.insert(queue, dep_node_key)
                            else
                                table.insert(ordered_nodes, dep_node_key)
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
                    table.insert(ordered_nodes, curr_node_key)
                end
            end
        end
    end
    return ordered_nodes
end

return DepGraph
