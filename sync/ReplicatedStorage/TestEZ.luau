--!nocheck
local _modules = {}
local function def(name, fn) _modules[name] = fn() end
local function get(name) return _modules[name] end
def("TestEnum", function()
	local T = {}
	T.TestStatus = { Success="Success", Failure="Failure", Skipped="Skipped" }
	T.NodeType = { Describe="Describe", It="It", BeforeAll="BeforeAll", AfterAll="AfterAll", BeforeEach="BeforeEach", AfterEach="AfterEach" }
	T.NodeModifier = { None="None", Skip="Skip", Focus="Focus" }
	return T
end)
def("Expectation", function()
	local Expectation = {}
	local SELF_KEYS = { to=true,be=true,been=true,have=true,was=true,at=true }
	local NEGATION_KEYS = { never=true }
	local function assertLevel(cond, msg, lvl)
		msg = msg or "Assertion failed!"; lvl = lvl or 1
		if not cond then error(msg, lvl+1) end
	end
	local function bindSelf(self, method)
		return function(firstArg, ...)
			if firstArg == self then return method(self, ...) else return method(self, firstArg, ...) end
		end
	end
	local function fmt(result, t, f) if result then return t else return f end end
	function Expectation.new(value)
		local self = { value=value, successCondition=true, condition=false, matchers={}, _boundMatchers={} }
		setmetatable(self, Expectation)
		self.a=bindSelf(self,self.a); self.an=self.a
		self.ok=bindSelf(self,self.ok); self.equal=bindSelf(self,self.equal)
		self.throw=bindSelf(self,self.throw); self.near=bindSelf(self,self.near)
		return self
	end
	function Expectation.checkMatcherNameCollisions(name)
		if SELF_KEYS[name] or NEGATION_KEYS[name] or Expectation[name] then return false end
		return true
	end
	function Expectation:extend(matchers)
		self.matchers = matchers or {}
		for name, impl in pairs(self.matchers) do
			self._boundMatchers[name] = bindSelf(self, function(_self, ...)
				local r = impl(self.value, ...)
				assertLevel(r.pass == self.successCondition, r.message, 3)
				self:_resetModifiers(); return self
			end)
		end
		return self
	end
	function Expectation.__index(self, key)
		if SELF_KEYS[key] then return self end
		if NEGATION_KEYS[key] then
			local n = Expectation.new(self.value):extend(self.matchers)
			n.successCondition = not self.successCondition; return n
		end
		if self._boundMatchers[key] then return self._boundMatchers[key] end
		return Expectation[key]
	end
	function Expectation:_resetModifiers() self.successCondition = true end
	function Expectation:a(typeName)
		local r = (type(self.value)==typeName)==self.successCondition
		assertLevel(r, fmt(self.successCondition,
			("Expected type %q, got %q of type %s"):format(typeName,tostring(self.value),type(self.value)),
			("Expected not type %q, got %q of type %s"):format(typeName,tostring(self.value),type(self.value))), 3)
		self:_resetModifiers(); return self
	end
	Expectation.an = Expectation.a
	function Expectation:ok()
		local r = (self.value~=nil)==self.successCondition
		assertLevel(r, fmt(self.successCondition,
			("Expected %q to be non-nil"):format(tostring(self.value)),
			("Expected %q to be nil"):format(tostring(self.value))), 3)
		self:_resetModifiers(); return self
	end
	function Expectation:equal(other)
		local r = (self.value==other)==self.successCondition
		assertLevel(r, fmt(self.successCondition,
			("Expected %q (%s), got %q (%s)"):format(tostring(other),type(other),tostring(self.value),type(self.value)),
			("Expected anything but %q (%s)"):format(tostring(other),type(other))), 3)
		self:_resetModifiers(); return self
	end
	function Expectation:near(other, limit)
		assert(type(self.value)=="number","value must be number for 'near'")
		limit = limit or 1e-7
		local r = (math.abs(self.value-other)<=limit)==self.successCondition
		assertLevel(r, fmt(self.successCondition,
			("Expected near %f (within %f) got %f"):format(other,limit,self.value),
			("Expected not near %f (within %f) got %f"):format(other,limit,self.value)), 3)
		self:_resetModifiers(); return self
	end
	function Expectation:throw(sub)
		local ok, err = pcall(self.value)
		local r = ok ~= self.successCondition
		if sub and not ok then
			if self.successCondition then r = err:find(sub,1,true)~=nil
			else r = err:find(sub,1,true)==nil end
		end
		local msg
		if sub then
			msg = fmt(self.successCondition,
				("Expected throw containing %q, got: %s"):format(sub, err and ("threw: "..err) or "no throw"),
				("Expected no throw containing %q, got: %s"):format(sub, tostring(err)))
		else
			msg = fmt(self.successCondition,
				"Expected throw, but no error.",
				("Expected no throw, got: %s"):format(tostring(err)))
		end
		assertLevel(r, msg, 3); self:_resetModifiers(); return self
	end
	return Expectation
end)

def("ExpectationContext", function()
	local Expectation = get("Expectation")
	local checkCollisions = Expectation.checkMatcherNameCollisions
	local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
	local EC = {}; EC.__index = EC
	function EC.new(parent)
		return setmetatable({ _extensions=parent and copy(parent._extensions) or {} }, EC)
	end
	function EC:startExpectationChain(...) return Expectation.new(...):extend(self._extensions) end
	function EC:extend(config)
		for k,v in pairs(config) do
			assert(self._extensions[k]==nil, ("Cannot reassign %q in expect.extend"):format(k))
			assert(checkCollisions(k), ("Cannot overwrite matcher %q"):format(k))
			self._extensions[k] = v
		end
	end
	return EC
end)

def("Context", function()
	local Context = {}
	function Context.new(parent)
		local meta, index = {}, {}
		meta.__index = index
		if parent then for k,v in pairs(getmetatable(parent).__index) do index[k]=v end end
		function meta.__newindex(_,k,v)
			assert(index[k]==nil, ("Cannot reassign %s in context"):format(tostring(k)))
			index[k]=v
		end
		return setmetatable({}, meta)
	end
	return Context
end)
def("LifecycleHooks", function()
	local TestEnum = get("TestEnum")
	local LH = {}; LH.__index = LH
	function LH.new() return setmetatable({_stack={}}, LH) end
	function LH:_getHooksOfType(nodes, key)
		local h={} for _,n in ipairs(nodes) do if n.type==key then h[#h+1]=n.callback end end return h
	end
	function LH:pushHooksFrom(planNode)
		assert(planNode~=nil)
		self._stack[#self._stack+1] = {
			[TestEnum.NodeType.BeforeAll] = self:_getHooksOfType(planNode.children,TestEnum.NodeType.BeforeAll),
			[TestEnum.NodeType.AfterAll]  = self:_getHooksOfType(planNode.children,TestEnum.NodeType.AfterAll),
			[TestEnum.NodeType.BeforeEach]= self:_getHooksOfType(planNode.children,TestEnum.NodeType.BeforeEach),
			[TestEnum.NodeType.AfterEach] = self:_getHooksOfType(planNode.children,TestEnum.NodeType.AfterEach),
		}
	end
	function LH:popHooks() table.remove(self._stack,#self._stack) end
	function LH:getBeforeAllHooks() return self._stack[#self._stack][TestEnum.NodeType.BeforeAll] end
	function LH:getAfterAllHooks()  return self._stack[#self._stack][TestEnum.NodeType.AfterAll]  end
	function LH:getBeforeEachHooks()
		local h={} for _,lvl in ipairs(self._stack) do for _,hk in ipairs(lvl[TestEnum.NodeType.BeforeEach]) do h[#h+1]=hk end end return h
	end
	function LH:getAfterEachHooks()
		local h={} for _,lvl in ipairs(self._stack) do for _,hk in ipairs(lvl[TestEnum.NodeType.AfterEach]) do table.insert(h,1,hk) end end return h
	end
	return LH
end)

def("TestResults", function()
	local TestEnum = get("TestEnum")
	local TR = {}; TR.__index = TR
	function TR.new(plan)
		return setmetatable({successCount=0,failureCount=0,skippedCount=0,planNode=plan,children={},errors={}}, TR)
	end
	function TR.createNode(planNode)
		return {planNode=planNode, children={}, errors={}, status=nil}
	end
	function TR:visitAllNodes(cb, root)
		root = root or self
		for _,child in ipairs(root.children) do cb(child); self:visitAllNodes(cb,child) end
	end
	return TR
end)
def("TestSession", function()
	local TestEnum = get("TestEnum"); local TestResults = get("TestResults")
	local Context = get("Context"); local EC = get("ExpectationContext")
	local TS = {}; TS.__index = TS
	function TS.new(plan)
		return setmetatable({results=TestResults.new(plan),nodeStack={},contextStack={},expectationContextStack={},hasFocusNodes=false}, TS)
	end
	function TS:calculateTotals()
		local r=self.results; r.successCount=0; r.failureCount=0; r.skippedCount=0
		r:visitAllNodes(function(node)
			local s,t = node.status, node.planNode.type
			if t==TestEnum.NodeType.It then
				if s==TestEnum.TestStatus.Success then r.successCount=r.successCount+1
				elseif s==TestEnum.TestStatus.Failure then r.failureCount=r.failureCount+1
				elseif s==TestEnum.TestStatus.Skipped then r.skippedCount=r.skippedCount+1 end
			end
		end)
	end
	function TS:gatherErrors()
		local r=self.results; r.errors={}
		r:visitAllNodes(function(node) for _,m in ipairs(node.errors) do r.errors[#r.errors+1]=m end end)
	end
	function TS:finalize()
		if #self.nodeStack~=0 then error("Cannot finalize with nodes on stack!",2) end
		self:calculateTotals(); self:gatherErrors(); return self.results
	end
	function TS:pushNode(planNode)
		local node = TestResults.createNode(planNode)
		local last = self.nodeStack[#self.nodeStack] or self.results
		last.children[#last.children+1] = node; self.nodeStack[#self.nodeStack+1] = node
		self.contextStack[#self.contextStack+1] = Context.new(self.contextStack[#self.contextStack])
		self.expectationContextStack[#self.expectationContextStack+1] = EC.new(self.expectationContextStack[#self.expectationContextStack])
	end
	function TS:popNode()
		assert(#self.nodeStack>0,"Empty node stack!")
		table.remove(self.nodeStack,#self.nodeStack)
		table.remove(self.contextStack,#self.contextStack)
		table.remove(self.expectationContextStack,#self.expectationContextStack)
	end
	function TS:getContext() assert(#self.contextStack>0,"Empty context stack!"); return self.contextStack[#self.contextStack] end
	function TS:getExpectationContext() assert(#self.expectationContextStack>0,"Empty ec stack!"); return self.expectationContextStack[#self.expectationContextStack] end
	function TS:shouldSkip()
		if self.hasFocusNodes then
			for i=#self.nodeStack,1,-1 do
				local m=self.nodeStack[i].planNode.modifier
				if m==TestEnum.NodeModifier.Skip then return true end
				if m==TestEnum.NodeModifier.Focus then return false end
			end
			return true
		else
			for i=#self.nodeStack,1,-1 do
				if self.nodeStack[i].planNode.modifier==TestEnum.NodeModifier.Skip then return true end
			end
		end
		return false
	end
	function TS:setSuccess() assert(#self.nodeStack>0); self.nodeStack[#self.nodeStack].status=TestEnum.TestStatus.Success end
	function TS:setSkipped() assert(#self.nodeStack>0); self.nodeStack[#self.nodeStack].status=TestEnum.TestStatus.Skipped end
	function TS:setError(msg)
		assert(#self.nodeStack>0); local last=self.nodeStack[#self.nodeStack]
		last.status=TestEnum.TestStatus.Failure; last.errors[#last.errors+1]=msg
	end
	function TS:addDummyError(phrase, msg)
		self:pushNode({type=TestEnum.NodeType.It,phrase=phrase}); self:setError(msg); self:popNode()
		self.nodeStack[#self.nodeStack].status=TestEnum.TestStatus.Failure
	end
	function TS:setStatusFromChildren()
		assert(#self.nodeStack>0); local last=self.nodeStack[#self.nodeStack]
		local status=TestEnum.TestStatus.Success; local skipped=true
		for _,child in ipairs(last.children) do
			if child.status~=TestEnum.TestStatus.Skipped then
				skipped=false
				if child.status==TestEnum.TestStatus.Failure then status=TestEnum.TestStatus.Failure end
			end
		end
		if skipped then status=TestEnum.TestStatus.Skipped end
		last.status=status
	end
	return TS
end)
def("TestPlan", function()
	local TestEnum = get("TestEnum"); local Expectation = get("Expectation")
	local function newEnv(currentNode, extraEnv)
		local env = {}
		if extraEnv then for k,v in pairs(extraEnv) do env[k]=v end end
		local function addChild(phrase, cb, nodeType, nodeMod)
			local node = currentNode:addChild(phrase, nodeType, nodeMod)
			node.callback = cb
			if nodeType==TestEnum.NodeType.Describe then node:expand() end
			return node
		end
		function env.describe(p,cb) addChild(p,cb,TestEnum.NodeType.Describe,TestEnum.NodeModifier.None) end
		function env.describeFOCUS(p,cb) addChild(p,cb,TestEnum.NodeType.Describe,TestEnum.NodeModifier.Focus) end
		function env.describeSKIP(p,cb) addChild(p,cb,TestEnum.NodeType.Describe,TestEnum.NodeModifier.Skip) end
		function env.it(p,cb) addChild(p,cb,TestEnum.NodeType.It,TestEnum.NodeModifier.None) end
		function env.itFOCUS(p,cb) addChild(p,cb,TestEnum.NodeType.It,TestEnum.NodeModifier.Focus) end
		function env.itSKIP(p,cb) addChild(p,cb,TestEnum.NodeType.It,TestEnum.NodeModifier.Skip) end
		function env.itFIXME(p,cb) local n=addChild(p,cb,TestEnum.NodeType.It,TestEnum.NodeModifier.Skip); warn("FIXME:",n:getFullName()) end
		local lcid = 0
		local lcMap = { [TestEnum.NodeType.BeforeAll]="beforeAll", [TestEnum.NodeType.AfterAll]="afterAll", [TestEnum.NodeType.BeforeEach]="beforeEach", [TestEnum.NodeType.AfterEach]="afterEach" }
		for nt, name in pairs(lcMap) do
			env[name] = function(cb) addChild(name.."_"..tostring(lcid),cb,nt,TestEnum.NodeModifier.None); lcid=lcid+1 end
		end
		function env.FIXME(msg) warn("FIXME:",currentNode:getFullName(),msg or ""); currentNode.modifier=TestEnum.NodeModifier.Skip end
		function env.FOCUS() currentNode.modifier=TestEnum.NodeModifier.Focus end
		function env.SKIP() currentNode.modifier=TestEnum.NodeModifier.Skip end
		function env.HACK_NO_XPCALL() warn("HACK_NO_XPCALL is deprecated.") end
		env.fit=env.itFOCUS; env.xit=env.itSKIP; env.fdescribe=env.describeFOCUS; env.xdescribe=env.describeSKIP
		env.expect = setmetatable({ extend=function() error('Cannot call expect.extend in describe') end },
			{ __call=function(_,...)  return Expectation.new(...) end })
		return env
	end
	local TestNode = {}; TestNode.__index = TestNode
	local function getMod(name, pattern, modifier)
		if pattern and (modifier==nil or modifier==TestEnum.NodeModifier.None) then
			if name:match(pattern) then return TestEnum.NodeModifier.Focus else return TestEnum.NodeModifier.Skip end
		end
		return modifier
	end
	function TestNode.new(plan, phrase, nodeType, nodeMod)
		nodeMod = nodeMod or TestEnum.NodeModifier.None
		local node = { plan=plan, phrase=phrase, type=nodeType, modifier=nodeMod, children={}, callback=nil, parent=nil }
		node.environment = newEnv(node, plan.extraEnvironment)
		return setmetatable(node, TestNode)
	end
	function TestNode:addChild(phrase, nodeType, nodeMod)
		if nodeType==TestEnum.NodeType.It then
			for _,c in pairs(self.children) do
				if c.phrase==phrase then error("Duplicate it block: "..c:getFullName()) end
			end
		end
		nodeMod = getMod(self:getFullName().." "..phrase, self.plan.testNamePattern, nodeMod)
		local child = TestNode.new(self.plan, phrase, nodeType, nodeMod)
		child.parent = self; self.children[#self.children+1] = child; return child
	end
	function TestNode:getFullName()
		if self.parent then local p=self.parent:getFullName(); if p then return p.." "..self.phrase end end
		return self.phrase
	end
	function TestNode:expand()
		local origEnv = getfenv(self.callback)
		local cbEnv = setmetatable({}, {__index=origEnv})
		for k,v in pairs(self.environment) do cbEnv[k]=v end
		cbEnv.script = origEnv.script
		setfenv(self.callback, cbEnv)
		local ok, err = xpcall(self.callback, function(m) return debug.traceback(tostring(m),2) end)
		if not ok then self.loadError = err end
	end
	local TestPlan = {}; TestPlan.__index = TestPlan
	function TestPlan.new(testNamePattern, extraEnvironment)
		return setmetatable({children={}, testNamePattern=testNamePattern, extraEnvironment=extraEnvironment}, TestPlan)
	end
	function TestPlan:addChild(phrase, nodeType, nodeMod)
		nodeMod = getMod(phrase, self.testNamePattern, nodeMod)
		local child = TestNode.new(self, phrase, nodeType, nodeMod)
		self.children[#self.children+1] = child; return child
	end
	function TestPlan:addRoot(path, method)
		local cur = self
		for i=#path,1,-1 do
			local next = nil
			for _,c in ipairs(cur.children) do if c.phrase==path[i] then next=c; break end end
			if next==nil then next=cur:addChild(path[i], TestEnum.NodeType.Describe) end
			cur = next
		end
		cur.callback = method; cur:expand()
	end
	function TestPlan:visitAllNodes(cb, root, level)
		root=root or self; level=level or 0
		for _,child in ipairs(root.children) do cb(child,level); self:visitAllNodes(cb,child,level+1) end
	end
	function TestPlan:findNodes(cb)
		local results={}
		self:visitAllNodes(function(node) if cb(node) then results[#results+1]=node end end)
		return results
	end
	return TestPlan
end)

def("TestPlanner", function()
	local TestPlan = get("TestPlan")
	local TP = {}
	function TP.createPlan(modulesList, testNamePattern, extraEnv)
		local plan = TestPlan.new(testNamePattern, extraEnv)
		table.sort(modulesList, function(a,b) return a.pathStringForSorting < b.pathStringForSorting end)
		for _,m in ipairs(modulesList) do plan:addRoot(m.path, m.method) end
		return plan
	end
	return TP
end)

def("TestRunner", function()
	local TestEnum = get("TestEnum"); local TestSession = get("TestSession"); local LH = get("LifecycleHooks")
	local RUNNING_GLOBAL = "__TESTEZ_RUNNING_TEST__"
	local TR = { environment={} }
	local function wrapEC(ec)
		return setmetatable({ extend=function(...) ec:extend(...) end },
			{ __call=function(_,...) return ec:startExpectationChain(...) end })
	end
	function TR.runPlan(plan)
		local session = TestSession.new(plan); local lh = LH.new()
		local excl = plan:findNodes(function(n) return n.modifier==TestEnum.NodeModifier.Focus end)
		session.hasFocusNodes = #excl > 0
		TR.runPlanNode(session, plan, lh); return session:finalize()
	end
	function TR.runPlanNode(session, planNode, lh)
		local function runCB(cb, prefix)
			local success=true; local errMsg; _G[RUNNING_GLOBAL]=true; prefix=prefix or ""
			local env = getfenv(cb)
			for k,v in pairs(TR.environment) do env[k]=v end
			env.fail = function(msg) success=false; errMsg=prefix..debug.traceback(tostring(msg or "fail() was called."),2) end
			env.expect = wrapEC(session:getExpectationContext())
			local ctx = session:getContext()
			local ok, res = xpcall(function() cb(ctx) end, function(m) return prefix..debug.traceback(tostring(m),2) end)
			if not ok then success=false; errMsg=res end
			_G[RUNNING_GLOBAL]=nil; return success, errMsg
		end
		local function runNode(cpn)
			for _,h in ipairs(lh:getBeforeEachHooks()) do local s,e=runCB(h,"beforeEach hook: "); if not s then return false,e end end
			local ts, te = runCB(cpn.callback)
			for _,h in ipairs(lh:getAfterEachHooks()) do
				local s,e=runCB(h,"afterEach hook: ")
				if not s then return false, not ts and (te.."\nAlso afterEach: "..e) or e end
			end
			if not ts then return false,te end; return true,nil
		end
		lh:pushHooksFrom(planNode)
		local halt=false
		for _,h in ipairs(lh:getBeforeAllHooks()) do
			local s,e=runCB(h,"beforeAll hook: "); if not s then session:addDummyError("beforeAll",e); halt=true end
		end
		if not halt then
			for _,cpn in ipairs(planNode.children) do
				if cpn.type==TestEnum.NodeType.It then
					session:pushNode(cpn)
					if session:shouldSkip() then session:setSkipped()
					else local s,e=runNode(cpn); if s then session:setSuccess() else session:setError(e) end end
					session:popNode()
				elseif cpn.type==TestEnum.NodeType.Describe then
					session:pushNode(cpn); TR.runPlanNode(session,cpn,lh)
					if cpn.loadError then session:setError("Error during planning: "..cpn.loadError)
					else session:setStatusFromChildren() end
					session:popNode()
				end
			end
		end
		for _,h in ipairs(lh:getAfterAllHooks()) do
			local s,e=runCB(h,"afterAll hook: "); if not s then session:addDummyError("afterAll",e) end
		end
		lh:popHooks()
	end
	return TR
end)
def("TextReporter", function()
	local TestEnum = get("TestEnum"); local INDENT=("   ")
	local SYM={[TestEnum.TestStatus.Success]="+",[TestEnum.TestStatus.Failure]="-",[TestEnum.TestStatus.Skipped]="~"}
	local TextReporter = {}
	local function cmp(a,b) return a.planNode.phrase:lower()<b.planNode.phrase:lower() end
	local function rNode(node, buf, lvl)
		buf=buf or{}; lvl=lvl or 0
		if node.status==TestEnum.TestStatus.Skipped then return buf end
		local line
		if node.status then line=("%s[%s] %s"):format(INDENT:rep(lvl),SYM[node.status] or "?",node.planNode.phrase)
		else line=("%s%s"):format(INDENT:rep(lvl),node.planNode.phrase) end
		buf[#buf+1]=line; table.sort(node.children,cmp)
		for _,c in ipairs(node.children) do rNode(c,buf,lvl+1) end; return buf
	end
	function TextReporter.report(results)
		local buf={}; table.sort(results.children,cmp)
		for _,c in ipairs(results.children) do rNode(c,buf,0) end
		print("Test results:\n"..table.concat(buf,"\n").."\n"..
			("%d passed, %d failed, %d skipped"):format(results.successCount,results.failureCount,results.skippedCount))
		if results.failureCount>0 then print(results.failureCount.." test nodes reported failures.") end
		if #results.errors>0 then
			print("Errors reported by tests:\n"); local TS=game:GetService("TestService")
			for _,m in ipairs(results.errors) do TS:Error(m); print("") end
		end
	end
	return TextReporter
end)

def("TextReporterQuiet", function()
	local TestEnum = get("TestEnum"); local INDENT=("   ")
	local SYM={[TestEnum.TestStatus.Success]="+",[TestEnum.TestStatus.Failure]="-",[TestEnum.TestStatus.Skipped]="~"}
	local TRQ = {}
	local function rNode(node, buf, lvl)
		buf=buf or{}; lvl=lvl or 0
		if node.status==TestEnum.TestStatus.Skipped then return buf end
		if node.status~=TestEnum.TestStatus.Success then
			buf[#buf+1]=("%s[%s] %s"):format(INDENT:rep(lvl),SYM[node.status] or "?",node.planNode.phrase)
		end
		for _,c in ipairs(node.children) do rNode(c,buf,lvl+1) end; return buf
	end
	function TRQ.report(results)
		local buf={}; for _,c in ipairs(results.children) do rNode(c,buf,0) end
		print("Test results:\n"..table.concat(buf,"\n").."\n"..
			("%d passed, %d failed, %d skipped"):format(results.successCount,results.failureCount,results.skippedCount))
		if results.failureCount>0 then print(results.failureCount.." test nodes reported failures.") end
		if #results.errors>0 then
			print("Errors:\n"); local TS=game:GetService("TestService")
			for _,m in ipairs(results.errors) do TS:Error(m); print("") end
		end
	end
	return TRQ
end)

def("TeamCityReporter", function()
	local TestEnum = get("TestEnum"); local TCR = {}
	local function esc(s) s=tostring(s); s=s:gsub("|","||"):gsub("]","|]"):gsub("'","|'"):gsub("%[","|["):gsub("\n","|n"):gsub("\r","|r"); return s end
	local function rNode(node, buf)
		buf=buf or{}
		if node.status==TestEnum.TestStatus.Skipped then return buf end
		if node.planNode.type==TestEnum.NodeType.Describe then
			buf[#buf+1]="##teamcity[testSuiteStarted name='"..esc(node.planNode.phrase).."']"
			for _,c in ipairs(node.children) do rNode(c,buf) end
			buf[#buf+1]="##teamcity[testSuiteFinished name='"..esc(node.planNode.phrase).."']"
		else
			local n=esc(node.planNode.phrase)
			buf[#buf+1]="##teamcity[testStarted name='"..n.."']"
			if node.status==TestEnum.TestStatus.Failure then
				local e=esc(#node.errors>0 and node.errors[1] or "Test failed")
				buf[#buf+1]="##teamcity[testFailed name='"..n.."' message='"..e.."']"
			end
			buf[#buf+1]="##teamcity[testFinished name='"..n.."']"
		end
		return buf
	end
	function TCR.report(results)
		local buf={}; for _,c in ipairs(results.children) do rNode(c,buf) end
		print(table.concat(buf,"\n"))
		print(("%d passed, %d failed, %d skipped"):format(results.successCount,results.failureCount,results.skippedCount))
		if #results.errors>0 then local TS=game:GetService("TestService"); for _,m in ipairs(results.errors) do TS:Error(m) end end
	end
	return TCR
end)

def("TestBootstrap", function()
	local TestPlanner=get("TestPlanner"); local TestRunner=get("TestRunner"); local TextReporter=get("TextReporter")
	local TB = {}
	local function stripSpec(n) return (n:gsub("%.spec$","")) end
	local function isSpec(s) return s:IsA("ModuleScript") and s.Name:match("%.spec$") end
	local function getPath(mod, root)
		root=root or game; local path={}; local last=mod
		if last.Name=="init.spec" then last=last.Parent end
		while last~=nil and last~=root do path[#path+1]=stripSpec(last.Name); last=last.Parent end
		path[#path+1]=stripSpec(root.Name); return path
	end
	local function toStrPath(p)
		local s=""; local first=true
		for _,e in ipairs(p) do if first then s=e; first=false else s=e.." "..s end end
		return s
	end
	function TB:getModulesImpl(root, modules, current)
		modules=modules or{}; current=current or root
		if isSpec(current) then
			local method=require(current); local path=getPath(current,root); local ps=toStrPath(path)
			modules[#modules+1]={method=method, path=path, pathStringForSorting=ps:lower()}
		end
	end
	function TB:getModules(root)
		local modules={}; self:getModulesImpl(root,modules)
		for _,c in ipairs(root:GetDescendants()) do self:getModulesImpl(root,modules,c) end
		return modules
	end
	function TB:run(roots, reporter, opts)
		reporter=reporter or TextReporter; opts=opts or {}
		if type(roots)~="table" then error(("Bad arg #1: expected table, got %s"):format(typeof(roots)),2) end
		local t0=tick(); local modules={}
		for _,r in ipairs(roots) do for _,m in ipairs(self:getModules(r)) do modules[#modules+1]=m end end
		local plan=TestPlanner.createPlan(modules, opts.testNamePattern, opts.extraEnvironment or {})
		local results=TestRunner.runPlan(plan)
		reporter.report(results)
		if opts.showTimingInfo then print(("Tests took %f seconds total"):format(tick()-t0)) end
		return results
	end
	return TB
end)

local TestEZ = {
	Expectation=get("Expectation"), TestBootstrap=get("TestBootstrap"), TestEnum=get("TestEnum"),
	TestPlan=get("TestPlan"), TestPlanner=get("TestPlanner"), TestResults=get("TestResults"),
	TestRunner=get("TestRunner"), TestSession=get("TestSession"),
	Reporters={ TextReporter=get("TextReporter"), TextReporterQuiet=get("TextReporterQuiet"), TeamCityReporter=get("TeamCityReporter") },
}
function TestEZ.run(root, cb)
	local m=TestEZ.TestBootstrap:getModules(root)
	local p=TestEZ.TestPlanner.createPlan(m)
	local r=TestEZ.TestRunner.runPlan(p)
	cb(r)
end
return TestEZ
