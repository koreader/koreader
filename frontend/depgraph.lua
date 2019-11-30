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

]]

local DepGraph = {}

function DepGraph:new(new_o)
    local o = new_o or {}
    o.nodes = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function DepGraph:addNode(node_key, deps)
    if not self.nodes[node_key] then
        self.nodes[node_key] = {}
    end
    if not deps then return end

    local node_deps = {}
    for _,dep_node_key in ipairs(deps) do
        if not self.nodes[dep_node_key] then
            self.nodes[dep_node_key] = {}
        end
        table.insert(node_deps, dep_node_key)
    end
    self.nodes[node_key].deps = node_deps
end

function DepGraph:removeNode(node_key)
    -- We should not remove it from self.nodes if it has
    -- a .deps array (it is the other nodes, that had this
    -- one in their override=, that have added themselves in
    -- this node's .deps). We don't want to lose these
    -- dependencies if we later re-addNode this node.
    local node = self.nodes[node_key]
    if node then
        if not node.deps or #node.deps == 0 then
            self.nodes[node_key] = nil
        end
    end
    -- But we should remove it from the .deps of other nodes.
    for curr_node_key, curr_node in pairs(self.nodes) do
        if curr_node.deps then
            local remove_idx
            for idx, dep_node_key in ipairs(self.nodes) do
                if dep_node_key == node_key then
                    remove_idx = idx
                    break
                end
            end
            if remove_idx then table.remove(curr_node.deps, remove_idx) end
        end
    end
end

function DepGraph:checkNode(id)
    if self.nodes[id] then
        return true
    else
        return false
    end
end

function DepGraph:addNodeDep(node_key, dep_node_key)
    local node = self.nodes[node_key]
    if not node then
        node = {}
        self.nodes[node_key] = node
    end
    if not node.deps then node.deps = {} end
    table.insert(node.deps, dep_node_key)
end

function DepGraph:removeNodeDep(node_key, dep_node_key)
    local node = self.nodes[node_key]
    if not node.deps then node.deps = {} end
    for i, dep_key in ipairs(node.deps) do
        if dep_key == dep_node_key then
            self.nodes[node_key]["deps"][i] = nil
        end
    end
end

function DepGraph:serialize()
    local visited = {}
    local ordered_nodes = {}
    for node_key,_ in pairs(self.nodes) do
        if not visited[node_key] then
            local queue = {node_key}
            while #queue > 0 do
                local pos = #queue
                local curr_node_key = queue[pos]
                local curr_node = self.nodes[curr_node_key]
                local all_deps_visited = true
                if curr_node.deps then
                    for _, dep_node_key in ipairs(curr_node.deps) do
                        if not visited[dep_node_key] then
                            -- only insert to queue for later process if node
                            -- has dependencies
                            if self.nodes[dep_node_key].deps then
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
