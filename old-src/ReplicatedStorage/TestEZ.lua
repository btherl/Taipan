--!nocheck
--[[
	TestEZ - BDD-style test and assertion library for Roblox
	Bundled single-file version from https://github.com/Roblox/testez (Apache 2.0)

	Usage:
		local TestEZ = require(ReplicatedStorage.TestEZ)
		local results = TestEZ.TestBootstrap:run({ testsFolder })
]]

-- ============================================================
-- Internal module registry (replaces script.* requires)
-- ============================================================
local _modules = {}

local function def(name, fn)
	_modules[name] = fn()
end

local function get(name)
	return _modules[name]
end

-- ============================================================
-- TestEnum
-- ============================================================
def("TestEnum", function()
	local TestEnum = {}

	TestEnum.TestStatus = {
		Success = "Success",
		Failure = "Failure",
		Skipped = "Skipped",
	}

	TestEnum.NodeType = {
		Describe   = "Describe",
		It         = "It",
		BeforeAll  = "BeforeAll",
		AfterAll   = "AfterAll",
		BeforeEach = "BeforeEach",
		AfterEach  = "AfterEach",
	}

	TestEnum.NodeModifier = {
		None  = "None",
		Skip  = "Skip",
		Focus = "Focus",
	}

	return TestEnum
end)

-- ============================================================
-- Expectation
-- ============================================================
def("Expectation", function()
	local Expectation = {}

	local SELF_KEYS = {
		to = true, be = true, been = true, have = true, was = true, at = true,
	}
	local NEGATION_KEYS = {
		never = true,
	}

	local function assertLevel(condition, message, level)
		message = message or "Assertion failed!"
		level = level or 1
		if not condition then
			error(message, level + 1)
		end
	end

	local function bindSelf(self, method)
		return function(firstArg, ...)
			if firstArg == self then
				return method(self, ...)
			else
				return method(self, firstArg, ...)
			end
		end
	end

	local function formatMessage(result, trueMessage, falseMessage)
		if result then
			return trueMessage
		else
			return falseMessage
		end
	end

	function Expectation.new(value)
		local self = {
			value = value,
			successCondition = true,
			condition = false,
			matchers = {},
			_boundMatchers = {},
		}
		setmetatable(self, Expectation)
		self.a     = bindSelf(self, self.a)
		self.an    = self.a
		self.ok    = bindSelf(self, self.ok)
		self.equal = bindSelf(self, self.equal)
		self.throw = bindSelf(self, self.throw)
		self.near  = bindSelf(self, self.near)
		return self
	end

	function Expectation.checkMatcherNameCollisions(name)
		if SELF_KEYS[name] or NEGATION_KEYS[name] or Expectation[name] then
			return false
		end
		return true
	end

	function Expectation:extend(matchers)
		self.matchers = matchers or {}
		for name, implementation in pairs(self.matchers) do
			self._boundMatchers[name] = bindSelf(self, function(_self, ...)
				local result = implementation(self.value, ...)
				local pass = result.pass == self.successCondition
				assertLevel(pass, result.message, 3)
				self:_resetModifiers()
				return self
			end)
		end
		return self
	end

	function Expectation.__index(self, key)
		if SELF_KEYS[key] then return self end
		if NEGATION_KEYS[key] then
			local newExpectation = Expectation.new(self.value):extend(self.matchers)
			newExpectation.successCondition = not self.successCondition
			return newExpectation
		end
		if self._boundMatchers[key] then return self._boundMatchers[key] end
		return Expectation[key]
	end

	function Expectation:_resetModifiers()
		self.successCondition = true
	end

	function Expectation:a(typeName)
		local result = (type(self.value) == typeName) == self.successCondition
		local message = formatMessage(self.successCondition,
			("Expected value of type %q, got value %q of type %s"):format(typeName, tostring(self.value), type(self.value)),
			("Expected value not of type %q, got value %q of type %s"):format(typeName, tostring(self.value), type(self.value))
		)
		assertLevel(result, message, 3)
		self:_resetModifiers()
		return self
	end
	Expectation.an = Expectation.a

	function Expectation:ok()
		local result = (self.value ~= nil) == self.successCondition
		local message = formatMessage(self.successCondition,
			("Expected value %q to be non-nil"):format(tostring(self.value)),
			("Expected value %q to be nil"):format(tostring(self.value))
		)
		assertLevel(result, message, 3)
		self:_resetModifiers()
		return self
	end

	function Expectation:equal(otherValue)
		local result = (self.value == otherValue) == self.successCondition
		local message = formatMessage(self.successCondition,
			("Expected value %q (%s), got %q (%s) instead"):format(tostring(otherValue), type(otherValue), tostring(self.value), type(self.value)),
			("Expected anything but value %q (%s)"):format(tostring(otherValue), type(otherValue))
		)
		assertLevel(result, message, 3)
		self:_resetModifiers()
		return self
	end

	function Expectation:near(otherValue, limit)
		assert(type(self.value) == "number", "Expectation value must be a number to use 'near'")
		assert(type(otherValue) == "number", "otherValue must be a number")
		assert(type(limit) == "number" or limit == nil, "limit must be a number or nil")
		limit = limit or 1e-7
		local result = (math.abs(self.value - otherValue) <= limit) == self.successCondition
		local message = formatMessage(self.successCondition,
			("Expected value to be near %f (within %f) but got %f instead"):format(otherValue, limit, self.value),
			("Expected value to not be near %f (within %f) but got %f instead"):format(otherValue, limit, self.value)
		)
		assertLevel(result, message, 3)
		self:_resetModifiers()
		return self
	end

	function Expectation:throw(messageSubstring)
		local ok, err = pcall(self.value)
		local result = ok ~= self.successCondition
		if messageSubstring and not ok then
			if self.successCondition then
				result = err:find(messageSubstring, 1, true) ~= nil
			else
				result = err:find(messageSubstring, 1, true) == nil
			end
		end
		local message
		if messageSubstring then
			message = formatMessage(self.successCondition,
				("Expected function to throw an error containing %q, but it %s"):format(
					messageSubstring, err and ("threw: %s"):format(err) or "did not throw."),
				("Expected function to never throw an error containing %q, but it threw: %s"):format(
					messageSubstring, tostring(err))
			)
		else
			message = formatMessage(self.successCondition,
				"Expected function to throw an error, but it did not throw.",
				("Expected function to succeed, but it threw an error: %s"):format(tostring(err))
			)
		end
		assertLevel(result, message, 3)
		self:_resetModifiers()
		return self
	end

	return Expectation
end)

-- ============================================================
-- ExpectationContext
-- ============================================================
def("ExpectationContext", function()
	local Expectation = get("Expectation")
	local checkMatcherNameCollisions = Expectation.checkMatcherNameCollisions

	local function copy(t)
		local result = {}
		for key, value in pairs(t) do result[key] = value end
		return result
	end

	local ExpectationContext = {}
	ExpectationContext.__index = ExpectationContext

	function ExpectationContext.new(parent)
		local self = {
			_extensions = parent and copy(parent._extensions) or {},
		}
		return setmetatable(self, ExpectationContext)
	end

	function ExpectationContext:startExpectationChain(...)
		return Expectation.new(...):extend(self._extensions)
	end

	function ExpectationContext:extend(config)
		for key, value in pairs(config) do
			assert(self._extensions[key] == nil,
				string.format("Cannot reassign %q in expect.extend", key))
			assert(checkMatcherNameCollisions(key),
				string.format("Cannot overwrite matcher %q; it already exists", key))
			self._extensions[key] = value
		end
	end

	return ExpectationContext
end)

-- ============================================================
-- Context
-- ============================================================
def("Context", function()
	local Context = {}

	function Context.new(parent)
		local meta = {}
		local index = {}
		meta.__index = index

		if parent then
			for key, value in pairs(getmetatable(parent).__index) do
				index[key] = value
			end
		end

		function meta.__newindex(_obj, key, value)
			assert(index[key] == nil,
				string.format("Cannot reassign %s in context", tostring(key)))
			index[key] = value
		end

		return setmetatable({}, meta)
	end

	return Context
end)

-- ============================================================
-- LifecycleHooks
-- ============================================================
def("LifecycleHooks", function()
	local TestEnum = get("TestEnum")

	local LifecycleHooks = {}
	LifecycleHooks.__index = LifecycleHooks

	function LifecycleHooks.new()
		local self = { _stack = {} }
		return setmetatable(self, LifecycleHooks)
	end

	function LifecycleHooks:getBeforeEachHooks()
		local key = TestEnum.NodeType.BeforeEach
		local hooks = {}
		for _, level in ipairs(self._stack) do
			for _, hook in ipairs(level[key]) do
				table.insert(hooks, hook)
			end
		end
		return hooks
	end

	function LifecycleHooks:getAfterEachHooks()
		local key = TestEnum.NodeType.AfterEach
		local hooks = {}
		for _, level in ipairs(self._stack) do
			for _, hook in ipairs(level[key]) do
				table.insert(hooks, 1, hook)
			end
		end
		return hooks
	end

	function LifecycleHooks:popHooks()
		table.remove(self._stack, #self._stack)
	end

	function LifecycleHooks:pushHooksFrom(planNode)
		assert(planNode ~= nil)
		table.insert(self._stack, {
			[TestEnum.NodeType.BeforeAll]  = self:_getHooksOfType(planNode.children, TestEnum.NodeType.BeforeAll),
			[TestEnum.NodeType.AfterAll]   = self:_getHooksOfType(planNode.children, TestEnum.NodeType.AfterAll),
			[TestEnum.NodeType.BeforeEach] = self:_getHooksOfType(planNode.children, TestEnum.NodeType.BeforeEach),
			[TestEnum.NodeType.AfterEach]  = self:_getHooksOfType(planNode.children, TestEnum.NodeType.AfterEach),
		})
	end

	function LifecycleHooks:getBeforeAllHooks()
		return self._stack[#self._stack][TestEnum.NodeType.BeforeAll]
	end

	function LifecycleHooks:getAfterAllHooks()
		return self._stack[#self._stack][TestEnum.NodeType.AfterAll]
	end

	function LifecycleHooks:_getHooksOfType(nodes, key)
		local hooks = {}
		for _, node in ipairs(nodes) do
			if node.type == key then
				table.insert(hooks, node.callback)
			end
		end
		return hooks
	end

	return LifecycleHooks
end)

-- ============================================================
-- TestResults
-- ============================================================
def("TestResults", function()
	local TestEnum = get("TestEnum")

	local STATUS_SYMBOLS = {
		[TestEnum.TestStatus.Success] = "+",
		[TestEnum.TestStatus.Failure] = "-",
		[TestEnum.TestStatus.Skipped] = "~",
	}

	local TestResults = {}
	TestResults.__index = TestResults

	function TestResults.new(plan)
		local self = {
			successCount = 0,
			failureCount = 0,
			skippedCount = 0,
			planNode = plan,
			children = {},
			errors = {},
		}
		setmetatable(self, TestResults)
		return self
	end

	function TestResults.createNode(planNode)
		return {
			planNode = planNode,
			children = {},
			errors = {},
			status = nil,
		}
	end

	function TestResults:visitAllNodes(callback, root)
		root = root or self
		for _, child in ipairs(root.children) do
			callback(child)
			self:visitAllNodes(callback, child)
		end
	end

	function TestResults:visualize(root, level)
		root = root or self
		level = level or 0
		local buffer = {}
		for _, child in ipairs(root.children) do
			if child.planNode.type == TestEnum.NodeType.It then
				local symbol = STATUS_SYMBOLS[child.status] or "?"
				local str = ("%s[%s] %s"):format((" "):rep(3 * level), symbol, child.planNode.phrase)
				if child.messages and #child.messages > 0 then
					str = str .. "\n " .. (" "):rep(3 * level) .. table.concat(child.messages, "\n " .. (" "):rep(3 * level))
				end
				table.insert(buffer, str)
			else
				local str = ("%s%s"):format((" "):rep(3 * level), child.planNode.phrase or "")
				if child.status then str = str .. (" (%s)"):format(child.status) end
				table.insert(buffer, str)
				if #child.children > 0 then
					table.insert(buffer, self:visualize(child, level + 1))
				end
			end
		end
		return table.concat(buffer, "\n")
	end

	return TestResults
end)

-- ============================================================
-- TestSession
-- ============================================================
def("TestSession", function()
	local TestEnum         = get("TestEnum")
	local TestResults      = get("TestResults")
	local Context          = get("Context")
	local ExpectationContext = get("ExpectationContext")

	local TestSession = {}
	TestSession.__index = TestSession

	function TestSession.new(plan)
		local self = {
			results = TestResults.new(plan),
			nodeStack = {},
			contextStack = {},
			expectationContextStack = {},
			hasFocusNodes = false,
		}
		setmetatable(self, TestSession)
		return self
	end

	function TestSession:calculateTotals()
		local results = self.results
		results.successCount = 0
		results.failureCount = 0
		results.skippedCount = 0
		results:visitAllNodes(function(node)
			local status   = node.status
			local nodeType = node.planNode.type
			if nodeType == TestEnum.NodeType.It then
				if status == TestEnum.TestStatus.Success then
					results.successCount = results.successCount + 1
				elseif status == TestEnum.TestStatus.Failure then
					results.failureCount = results.failureCount + 1
				elseif status == TestEnum.TestStatus.Skipped then
					results.skippedCount = results.skippedCount + 1
				end
			end
		end)
	end

	function TestSession:gatherErrors()
		local results = self.results
		results.errors = {}
		results:visitAllNodes(function(node)
			if #node.errors > 0 then
				for _, message in ipairs(node.errors) do
					table.insert(results.errors, message)
				end
			end
		end)
	end

	function TestSession:finalize()
		if #self.nodeStack ~= 0 then
			error("Cannot finalize TestResults with nodes still on the stack!", 2)
		end
		self:calculateTotals()
		self:gatherErrors()
		return self.results
	end

	function TestSession:pushNode(planNode)
		local node = TestResults.createNode(planNode)
		local lastNode = self.nodeStack[#self.nodeStack] or self.results
		table.insert(lastNode.children, node)
		table.insert(self.nodeStack, node)

		local lastContext = self.contextStack[#self.contextStack]
		local context = Context.new(lastContext)
		table.insert(self.contextStack, context)

		local lastExpectationContext = self.expectationContextStack[#self.expectationContextStack]
		local expectationContext = ExpectationContext.new(lastExpectationContext)
		table.insert(self.expectationContextStack, expectationContext)
	end

	function TestSession:popNode()
		assert(#self.nodeStack > 0, "Tried to pop from an empty node stack!")
		table.remove(self.nodeStack, #self.nodeStack)
		table.remove(self.contextStack, #self.contextStack)
		table.remove(self.expectationContextStack, #self.expectationContextStack)
	end

	function TestSession:getContext()
		assert(#self.contextStack > 0, "Tried to get context from an empty stack!")
		return self.contextStack[#self.contextStack]
	end

	function TestSession:getExpectationContext()
		assert(#self.expectationContextStack > 0, "Tried to get expectationContext from an empty stack!")
		return self.expectationContextStack[#self.expectationContextStack]
	end

	function TestSession:shouldSkip()
		if self.hasFocusNodes then
			for i = #self.nodeStack, 1, -1 do
				local node = self.nodeStack[i]
				if node.planNode.modifier == TestEnum.NodeModifier.Skip  then return true  end
				if node.planNode.modifier == TestEnum.NodeModifier.Focus then return false end
			end
			return true
		else
			for i = #self.nodeStack, 1, -1 do
				local node = self.nodeStack[i]
				if node.planNode.modifier == TestEnum.NodeModifier.Skip then return true end
			end
		end
		return false
	end

	function TestSession:setSuccess()
		assert(#self.nodeStack > 0, "Attempting to set success status on empty stack")
		self.nodeStack[#self.nodeStack].status = TestEnum.TestStatus.Success
	end

	function TestSession:setSkipped()
		assert(#self.nodeStack > 0, "Attempting to set skipped status on empty stack")
		self.nodeStack[#self.nodeStack].status = TestEnum.TestStatus.Skipped
	end

	function TestSession:setError(message)
		assert(#self.nodeStack > 0, "Attempting to set error status on empty stack")
		local last = self.nodeStack[#self.nodeStack]
		last.status = TestEnum.TestStatus.Failure
		table.insert(last.errors, message)
	end

	function TestSession:addDummyError(phrase, message)
		self:pushNode({ type = TestEnum.NodeType.It, phrase = phrase })
		self:setError(message)
		self:popNode()
		self.nodeStack[#self.nodeStack].status = TestEnum.TestStatus.Failure
	end

	function TestSession:setStatusFromChildren()
		assert(#self.nodeStack > 0, "Attempting to set status from children on empty stack")
		local last = self.nodeStack[#self.nodeStack]
		local status = TestEnum.TestStatus.Success
		local skipped = true
		for _, child in ipairs(last.children) do
			if child.status ~= TestEnum.TestStatus.Skipped then
				skipped = false
				if child.status == TestEnum.TestStatus.Failure then
					status = TestEnum.TestStatus.Failure
				end
			end
		end
		if skipped then status = TestEnum.TestStatus.Skipped end
		last.status = status
	end

	return TestSession
end)

-- ============================================================
-- TestPlan
-- ============================================================
def("TestPlan", function()
	local TestEnum   = get("TestEnum")
	local Expectation = get("Expectation")

	local function newEnvironment(currentNode, extraEnvironment)
		local env = {}

		if extraEnvironment then
			if type(extraEnvironment) ~= "table" then
				error(("Bad argument #2 to newEnvironment. Expected table, got %s"):format(typeof(extraEnvironment)), 2)
			end
			for key, value in pairs(extraEnvironment) do
				env[key] = value
			end
		end

		local function addChild(phrase, callback, nodeType, nodeModifier)
			local node = currentNode:addChild(phrase, nodeType, nodeModifier)
			node.callback = callback
			if nodeType == TestEnum.NodeType.Describe then
				node:expand()
			end
			return node
		end

		function env.describeFOCUS(phrase, callback)
			addChild(phrase, callback, TestEnum.NodeType.Describe, TestEnum.NodeModifier.Focus)
		end
		function env.describeSKIP(phrase, callback)
			addChild(phrase, callback, TestEnum.NodeType.Describe, TestEnum.NodeModifier.Skip)
		end
		function env.describe(phrase, callback)
			addChild(phrase, callback, TestEnum.NodeType.Describe, TestEnum.NodeModifier.None)
		end
		function env.itFOCUS(phrase, callback)
			addChild(phrase, callback, TestEnum.NodeType.It, TestEnum.NodeModifier.Focus)
		end
		function env.itSKIP(phrase, callback)
			addChild(phrase, callback, TestEnum.NodeType.It, TestEnum.NodeModifier.Skip)
		end
		function env.itFIXME(phrase, callback)
			local node = addChild(phrase, callback, TestEnum.NodeType.It, TestEnum.NodeModifier.Skip)
			warn("FIXME: broken test", node:getFullName())
		end
		function env.it(phrase, callback)
			addChild(phrase, callback, TestEnum.NodeType.It, TestEnum.NodeModifier.None)
		end

		local lifecyclePhaseId = 0
		local lifecycleHooks = {
			[TestEnum.NodeType.BeforeAll]  = "beforeAll",
			[TestEnum.NodeType.AfterAll]   = "afterAll",
			[TestEnum.NodeType.BeforeEach] = "beforeEach",
			[TestEnum.NodeType.AfterEach]  = "afterEach",
		}
		for nodeType, name in pairs(lifecycleHooks) do
			env[name] = function(callback)
				addChild(name .. "_" .. tostring(lifecyclePhaseId), callback, nodeType, TestEnum.NodeModifier.None)
				lifecyclePhaseId = lifecyclePhaseId + 1
			end
		end

		function env.FIXME(optionalMessage)
			warn("FIXME: broken test", currentNode:getFullName(), optionalMessage or "")
			currentNode.modifier = TestEnum.NodeModifier.Skip
		end
		function env.FOCUS()
			currentNode.modifier = TestEnum.NodeModifier.Focus
		end
		function env.SKIP()
			currentNode.modifier = TestEnum.NodeModifier.Skip
		end
		function env.HACK_NO_XPCALL()
			warn("HACK_NO_XPCALL is deprecated. It is now safe to yield in an xpcall, so this is no longer necessary.")
		end

		env.fit       = env.itFOCUS
		env.xit       = env.itSKIP
		env.fdescribe = env.describeFOCUS
		env.xdescribe = env.describeSKIP

		env.expect = setmetatable({
			extend = function(...)
				error('Cannot call "expect.extend" from within a "describe" node.')
			end,
		}, {
			__call = function(_self, ...)
				return Expectation.new(...)
			end,
		})

		return env
	end

	local TestNode = {}
	TestNode.__index = TestNode

	function TestNode.new(plan, phrase, nodeType, nodeModifier)
		nodeModifier = nodeModifier or TestEnum.NodeModifier.None
		local node = {
			plan      = plan,
			phrase    = phrase,
			type      = nodeType,
			modifier  = nodeModifier,
			children  = {},
			callback  = nil,
			parent    = nil,
		}
		node.environment = newEnvironment(node, plan.extraEnvironment)
		return setmetatable(node, TestNode)
	end

	local function getModifier(name, pattern, modifier)
		if pattern and (modifier == nil or modifier == TestEnum.NodeModifier.None) then
			if name:match(pattern) then
				return TestEnum.NodeModifier.Focus
			else
				return TestEnum.NodeModifier.Skip
			end
		end
		return modifier
	end

	function TestNode:addChild(phrase, nodeType, nodeModifier)
		if nodeType == TestEnum.NodeType.It then
			for _, child in pairs(self.children) do
				if child.phrase == phrase then
					error("Duplicate it block found: " .. child:getFullName())
				end
			end
		end
		local childName = self:getFullName() .. " " .. phrase
		nodeModifier = getModifier(childName, self.plan.testNamePattern, nodeModifier)
		local child = TestNode.new(self.plan, phrase, nodeType, nodeModifier)
		child.parent = self
		table.insert(self.children, child)
		return child
	end

	function TestNode:getFullName()
		if self.parent then
			local parentPhrase = self.parent:getFullName()
			if parentPhrase then
				return parentPhrase .. " " .. self.phrase
			end
		end
		return self.phrase
	end

	function TestNode:expand()
		local originalEnv = getfenv(self.callback)
		local callbackEnv = setmetatable({}, { __index = originalEnv })
		for key, value in pairs(self.environment) do
			callbackEnv[key] = value
		end
		callbackEnv.script = originalEnv.script
		setfenv(self.callback, callbackEnv)

		local success, result = xpcall(self.callback, function(message)
			return debug.traceback(tostring(message), 2)
		end)
		if not success then
			self.loadError = result
		end
	end

	local TestPlan = {}
	TestPlan.__index = TestPlan

	function TestPlan.new(testNamePattern, extraEnvironment)
		local plan = {
			children = {},
			testNamePattern = testNamePattern,
			extraEnvironment = extraEnvironment,
		}
		return setmetatable(plan, TestPlan)
	end

	function TestPlan:addChild(phrase, nodeType, nodeModifier)
		nodeModifier = getModifier(phrase, self.testNamePattern, nodeModifier)
		local child = TestNode.new(self, phrase, nodeType, nodeModifier)
		table.insert(self.children, child)
		return child
	end

	function TestPlan:addRoot(path, method)
		local curNode = self
		for i = #path, 1, -1 do
			local nextNode = nil
			for _, child in ipairs(curNode.children) do
				if child.phrase == path[i] then
					nextNode = child
					break
				end
			end
			if nextNode == nil then
				nextNode = curNode:addChild(path[i], TestEnum.NodeType.Describe)
			end
			curNode = nextNode
		end
		curNode.callback = method
		curNode:expand()
	end

	function TestPlan:visitAllNodes(callback, root, level)
		root  = root  or self
		level = level or 0
		for _, child in ipairs(root.children) do
			callback(child, level)
			self:visitAllNodes(callback, child, level + 1)
		end
	end

	function TestPlan:visualize()
		local buffer = {}
		self:visitAllNodes(function(node, level)
			table.insert(buffer, (" "):rep(3 * level) .. node.phrase)
		end)
		return table.concat(buffer, "\n")
	end

	function TestPlan:findNodes(callback)
		local results = {}
		self:visitAllNodes(function(node)
			if callback(node) then
				table.insert(results, node)
			end
		end)
		return results
	end

	return TestPlan
end)

-- ============================================================
-- TestPlanner
-- ============================================================
def("TestPlanner", function()
	local TestPlan = get("TestPlan")

	local TestPlanner = {}

	function TestPlanner.createPlan(modulesList, testNamePattern, extraEnvironment)
		local plan = TestPlan.new(testNamePattern, extraEnvironment)
		table.sort(modulesList, function(a, b)
			return a.pathStringForSorting < b.pathStringForSorting
		end)
		for _, module in ipairs(modulesList) do
			plan:addRoot(module.path, module.method)
		end
		return plan
	end

	return TestPlanner
end)

-- ============================================================
-- TestRunner
-- ============================================================
def("TestRunner", function()
	local TestEnum       = get("TestEnum")
	local TestSession    = get("TestSession")
	local LifecycleHooks = get("LifecycleHooks")

	local RUNNING_GLOBAL = "__TESTEZ_RUNNING_TEST__"

	local TestRunner = { environment = {} }

	local function wrapExpectContextWithPublicApi(expectationContext)
		return setmetatable({
			extend = function(...)
				expectationContext:extend(...)
			end,
		}, {
			__call = function(_self, ...)
				return expectationContext:startExpectationChain(...)
			end,
		})
	end

	function TestRunner.runPlan(plan)
		local session        = TestSession.new(plan)
		local lifecycleHooks = LifecycleHooks.new()

		local exclusiveNodes = plan:findNodes(function(node)
			return node.modifier == TestEnum.NodeModifier.Focus
		end)
		session.hasFocusNodes = #exclusiveNodes > 0

		TestRunner.runPlanNode(session, plan, lifecycleHooks)
		return session:finalize()
	end

	function TestRunner.runPlanNode(session, planNode, lifecycleHooks)
		local function runCallback(callback, messagePrefix)
			local success = true
			local errorMessage
			_G[RUNNING_GLOBAL] = true
			messagePrefix = messagePrefix or ""

			local testEnvironment = getfenv(callback)
			for key, value in pairs(TestRunner.environment) do
				testEnvironment[key] = value
			end

			testEnvironment.fail = function(message)
				if message == nil then message = "fail() was called." end
				success = false
				errorMessage = messagePrefix .. debug.traceback(tostring(message), 2)
			end

			testEnvironment.expect = wrapExpectContextWithPublicApi(session:getExpectationContext())

			local context = session:getContext()
			local nodeSuccess, nodeResult = xpcall(
				function() callback(context) end,
				function(message)
					return messagePrefix .. debug.traceback(tostring(message), 2)
				end
			)

			if not nodeSuccess then
				success = false
				errorMessage = nodeResult
			end

			_G[RUNNING_GLOBAL] = nil
			return success, errorMessage
		end

		local function runNode(childPlanNode)
			for _, hook in ipairs(lifecycleHooks:getBeforeEachHooks()) do
				local success, errorMessage = runCallback(hook, "beforeEach hook: ")
				if not success then return false, errorMessage end
			end

			local testSuccess, testErrorMessage = runCallback(childPlanNode.callback)

			for _, hook in ipairs(lifecycleHooks:getAfterEachHooks()) do
				local success, errorMessage = runCallback(hook, "afterEach hook: ")
				if not success then
					if not testSuccess then
						return false, testErrorMessage .. "\nWhile cleaning up the failed test another error was found:\n" .. errorMessage
					end
					return false, errorMessage
				end
			end

			if not testSuccess then return false, testErrorMessage end
			return true, nil
		end

		lifecycleHooks:pushHooksFrom(planNode)

		local halt = false
		for _, hook in ipairs(lifecycleHooks:getBeforeAllHooks()) do
			local success, errorMessage = runCallback(hook, "beforeAll hook: ")
			if not success then
				session:addDummyError("beforeAll", errorMessage)
				halt = true
			end
		end

		if not halt then
			for _, childPlanNode in ipairs(planNode.children) do
				if childPlanNode.type == TestEnum.NodeType.It then
					session:pushNode(childPlanNode)
					if session:shouldSkip() then
						session:setSkipped()
					else
						local success, errorMessage = runNode(childPlanNode)
						if success then
							session:setSuccess()
						else
							session:setError(errorMessage)
						end
					end
					session:popNode()
				elseif childPlanNode.type == TestEnum.NodeType.Describe then
					session:pushNode(childPlanNode)
					TestRunner.runPlanNode(session, childPlanNode, lifecycleHooks)
					if childPlanNode.loadError then
						local message = "Error during planning: " .. childPlanNode.loadError
						session:setError(message)
					else
						session:setStatusFromChildren()
					end
					session:popNode()
				end
			end
		end

		for _, hook in ipairs(lifecycleHooks:getAfterAllHooks()) do
			local success, errorMessage = runCallback(hook, "afterAll hook: ")
			if not success then
				session:addDummyError("afterAll", errorMessage)
			end
		end

		lifecycleHooks:popHooks()
	end

	return TestRunner
end)

-- ============================================================
-- Reporters / TextReporter
-- ============================================================
def("TextReporter", function()
	local TestEnum = get("TestEnum")

	local INDENT = (" "):rep(3)
	local STATUS_SYMBOLS = {
		[TestEnum.TestStatus.Success] = "+",
		[TestEnum.TestStatus.Failure] = "-",
		[TestEnum.TestStatus.Skipped] = "~",
	}
	local UNKNOWN_STATUS_SYMBOL = "?"

	local TextReporter = {}

	local function compareNodes(a, b)
		return a.planNode.phrase:lower() < b.planNode.phrase:lower()
	end

	local function reportNode(node, buffer, level)
		buffer = buffer or {}
		level  = level  or 0
		if node.status == TestEnum.TestStatus.Skipped then return buffer end
		local line
		if node.status then
			local symbol = STATUS_SYMBOLS[node.status] or UNKNOWN_STATUS_SYMBOL
			line = ("%s[%s] %s"):format(INDENT:rep(level), symbol, node.planNode.phrase)
		else
			line = ("%s%s"):format(INDENT:rep(level), node.planNode.phrase)
		end
		table.insert(buffer, line)
		table.sort(node.children, compareNodes)
		for _, child in ipairs(node.children) do
			reportNode(child, buffer, level + 1)
		end
		return buffer
	end

	local function reportRoot(node)
		local buffer = {}
		table.sort(node.children, compareNodes)
		for _, child in ipairs(node.children) do
			reportNode(child, buffer, 0)
		end
		return buffer
	end

	local function report(root)
		return table.concat(reportRoot(root), "\n")
	end

	function TextReporter.report(results)
		local resultBuffer = {
			"Test results:",
			report(results),
			("%d passed, %d failed, %d skipped"):format(
				results.successCount, results.failureCount, results.skippedCount),
		}
		print(table.concat(resultBuffer, "\n"))

		if results.failureCount > 0 then
			print(("%d test nodes reported failures."):format(results.failureCount))
		end

		if #results.errors > 0 then
			print("Errors reported by tests:")
			print("")
			local TestService = game:GetService("TestService")
			for _, message in ipairs(results.errors) do
				TestService:Error(message)
				print("")
			end
		end
	end

	return TextReporter
end)

-- ============================================================
-- Reporters / TextReporterQuiet
-- ============================================================
def("TextReporterQuiet", function()
	local TestEnum = get("TestEnum")

	local INDENT = (" "):rep(3)
	local STATUS_SYMBOLS = {
		[TestEnum.TestStatus.Success] = "+",
		[TestEnum.TestStatus.Failure] = "-",
		[TestEnum.TestStatus.Skipped] = "~",
	}
	local UNKNOWN_STATUS_SYMBOL = "?"

	local TextReporterQuiet = {}

	local function reportNode(node, buffer, level)
		buffer = buffer or {}
		level  = level  or 0
		if node.status == TestEnum.TestStatus.Skipped then return buffer end
		local line
		if node.status ~= TestEnum.TestStatus.Success then
			local symbol = STATUS_SYMBOLS[node.status] or UNKNOWN_STATUS_SYMBOL
			line = ("%s[%s] %s"):format(INDENT:rep(level), symbol, node.planNode.phrase)
		end
		table.insert(buffer, line)
		for _, child in ipairs(node.children) do
			reportNode(child, buffer, level + 1)
		end
		return buffer
	end

	local function reportRoot(node)
		local buffer = {}
		for _, child in ipairs(node.children) do
			reportNode(child, buffer, 0)
		end
		return buffer
	end

	local function report(root)
		return table.concat(reportRoot(root), "\n")
	end

	function TextReporterQuiet.report(results)
		local resultBuffer = {
			"Test results:",
			report(results),
			("%d passed, %d failed, %d skipped"):format(
				results.successCount, results.failureCount, results.skippedCount),
		}
		print(table.concat(resultBuffer, "\n"))

		if results.failureCount > 0 then
			print(("%d test nodes reported failures."):format(results.failureCount))
		end

		if #results.errors > 0 then
			print("Errors reported by tests:")
			print("")
			local TestService = game:GetService("TestService")
			for _, message in ipairs(results.errors) do
				TestService:Error(message)
				print("")
			end
		end
	end

	return TextReporterQuiet
end)

-- ============================================================
-- Reporters / TeamCityReporter
-- ============================================================
def("TeamCityReporter", function()
	local TestEnum = get("TestEnum")

	local TeamCityReporter = {}

	local function teamCityEscape(str)
		str = tostring(str)
		str = str:gsub("|",  "||")
		str = str:gsub("]",  "|]")
		str = str:gsub("'",  "|'")
		str = str:gsub("%[", "|[")
		str = str:gsub("\n", "|n")
		str = str:gsub("\r", "|r")
		return str
	end

	local function teamCityEnterSuite(name)
		return ("##teamcity[testSuiteStarted name='%s']"):format(teamCityEscape(name))
	end

	local function teamCityLeaveSuite(name)
		return ("##teamcity[testSuiteFinished name='%s']"):format(teamCityEscape(name))
	end

	local function teamCityEnterCase(name)
		return ("##teamcity[testStarted name='%s']"):format(teamCityEscape(name))
	end

	local function teamCityLeaveCase(name)
		return ("##teamcity[testFinished name='%s']"):format(teamCityEscape(name))
	end

	local function teamCityFailCase(name, message)
		return ("##teamcity[testFailed name='%s' message='%s']"):format(
			teamCityEscape(name), teamCityEscape(message))
	end

	local function reportNode(node, buffer)
		buffer = buffer or {}
		if node.status == TestEnum.TestStatus.Skipped then return buffer end

		if node.planNode.type == TestEnum.NodeType.Describe then
			table.insert(buffer, teamCityEnterSuite(node.planNode.phrase))
			for _, child in ipairs(node.children) do
				reportNode(child, buffer)
			end
			table.insert(buffer, teamCityLeaveSuite(node.planNode.phrase))
		else
			table.insert(buffer, teamCityEnterCase(node.planNode.phrase))
			if node.status == TestEnum.TestStatus.Failure then
				local errorMsg = #node.errors > 0 and node.errors[1] or "Test failed"
				table.insert(buffer, teamCityFailCase(node.planNode.phrase, errorMsg))
			end
			table.insert(buffer, teamCityLeaveCase(node.planNode.phrase))
		end

		return buffer
	end

	function TeamCityReporter.report(results)
		local buffer = {}
		for _, child in ipairs(results.children) do
			reportNode(child, buffer)
		end

		print(table.concat(buffer, "\n"))
		print(("%d passed, %d failed, %d skipped"):format(
			results.successCount, results.failureCount, results.skippedCount))

		if results.failureCount > 0 then
			print(("%d test nodes reported failures."):format(results.failureCount))
		end

		if #results.errors > 0 then
			print("Errors reported by tests:")
			local TestService = game:GetService("TestService")
			for _, message in ipairs(results.errors) do
				TestService:Error(message)
			end
		end
	end

	return TeamCityReporter
end)

-- ============================================================
-- TestBootstrap
-- ============================================================
def("TestBootstrap", function()
	local TestPlanner   = get("TestPlanner")
	local TestRunner    = get("TestRunner")
	local TextReporter  = get("TextReporter")

	local TestBootstrap = {}

	local function stripSpecSuffix(name)
		return (name:gsub("%.spec$", ""))
	end

	local function isSpecScript(aScript)
		return aScript:IsA("ModuleScript") and aScript.Name:match("%.spec$")
	end

	local function getPath(module, root)
		root = root or game
		local path = {}
		local last = module

		if last.Name == "init.spec" then
			last = last.Parent
		end

		while last ~= nil and last ~= root do
			table.insert(path, stripSpecSuffix(last.Name))
			last = last.Parent
		end
		table.insert(path, stripSpecSuffix(root.Name))
		return path
	end

	local function toStringPath(tablePath)
		local stringPath = ""
		local first = true
		for _, element in ipairs(tablePath) do
			if first then
				stringPath = element
				first = false
			else
				stringPath = element .. " " .. stringPath
			end
		end
		return stringPath
	end

	function TestBootstrap:getModulesImpl(root, modules, current)
		modules = modules or {}
		current = current or root

		if isSpecScript(current) then
			local method = require(current)
			local path = getPath(current, root)
			local pathString = toStringPath(path)
			table.insert(modules, {
				method = method,
				path = path,
				pathStringForSorting = pathString:lower(),
			})
		end
	end

	function TestBootstrap:getModules(root)
		local modules = {}
		self:getModulesImpl(root, modules)
		for _, child in ipairs(root:GetDescendants()) do
			self:getModulesImpl(root, modules, child)
		end
		return modules
	end

	function TestBootstrap:run(roots, reporter, otherOptions)
		reporter = reporter or TextReporter
		otherOptions = otherOptions or {}
		local showTimingInfo   = otherOptions["showTimingInfo"] or false
		local testNamePattern  = otherOptions["testNamePattern"]
		local extraEnvironment = otherOptions["extraEnvironment"] or {}

		if type(roots) ~= "table" then
			error(("Bad argument #1 to TestBootstrap:run. Expected table, got %s"):format(typeof(roots)), 2)
		end

		local startTime = tick()
		local modules = {}
		for _, subRoot in ipairs(roots) do
			local newModules = self:getModules(subRoot)
			for _, newModule in ipairs(newModules) do
				table.insert(modules, newModule)
			end
		end

		local afterModules = tick()
		local plan = TestPlanner.createPlan(modules, testNamePattern, extraEnvironment)
		local afterPlan = tick()
		local results = TestRunner.runPlan(plan)
		local afterRun = tick()
		reporter.report(results)
		local afterReport = tick()

		if showTimingInfo then
			local timing = {
				("Took %f seconds to locate test modules"):format(afterModules - startTime),
				("Took %f seconds to create test plan"):format(afterPlan - afterModules),
				("Took %f seconds to run tests"):format(afterRun - afterPlan),
				("Took %f seconds to report tests"):format(afterReport - afterRun),
			}
			print(table.concat(timing, "\n"))
		end

		return results
	end

	return TestBootstrap
end)

-- ============================================================
-- Public API
-- ============================================================
local TestEZ = {
	Expectation         = get("Expectation"),
	TestBootstrap       = get("TestBootstrap"),
	TestEnum            = get("TestEnum"),
	TestPlan            = get("TestPlan"),
	TestPlanner         = get("TestPlanner"),
	TestResults         = get("TestResults"),
	TestRunner          = get("TestRunner"),
	TestSession         = get("TestSession"),

	Reporters = {
		TextReporter      = get("TextReporter"),
		TextReporterQuiet = get("TextReporterQuiet"),
		TeamCityReporter  = get("TeamCityReporter"),
	},
}

function TestEZ.run(testRoot, callback)
	local modules = TestEZ.TestBootstrap:getModules(testRoot)
	local plan    = TestEZ.TestPlanner.createPlan(modules)
	local results = TestEZ.TestRunner.runPlan(plan)
	callback(results)
end

return TestEZ
