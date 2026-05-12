-- ShipSpriteData.spec.lua
-- Tests for the pure ship-sprite data module.

return function()
	local ShipSpriteData = require(game:GetService("StarterGui").TaipanGui.GameController.Apple2.ShipSpriteData)

	describe("baseSprite", function()
		it("is a 5-row table of 7-char strings", function()
			local rows = ShipSpriteData.baseSprite
			expect(#rows).to.equal(5)
			for i = 1, 5 do
				expect(#rows[i]).to.equal(7)
			end
		end)

		it("matches the BASIC string ABCDEFG / HIJKLMN / OIJKLPQ / RSTUVWX / YJJJJJZ", function()
			local rows = ShipSpriteData.baseSprite
			expect(rows[1]).to.equal("ABCDEFG")
			expect(rows[2]).to.equal("HIJKLMN")
			expect(rows[3]).to.equal("OIJKLPQ")
			expect(rows[4]).to.equal("RSTUVWX")
			expect(rows[5]).to.equal("YJJJJJZ")
		end)
	end)

	describe("damageFragments", function()
		it("has 6 entries, each with two zones (J=0 upper, J=1 lower)", function()
			expect(#ShipSpriteData.damageFragments).to.equal(6)
			for i = 1, 6 do
				local entry = ShipSpriteData.damageFragments[i]
				expect(entry[0]).to.be.ok()
				expect(entry[1]).to.be.ok()
				expect(type(entry[0].chars)).to.equal("table")
				expect(type(entry[1].chars)).to.equal("table")
				expect(type(entry[0].dx)).to.equal("number")
				expect(type(entry[0].dy)).to.equal("number")
			end
		end)

		it("upper-zone (J=0) Y offsets are all 0..2", function()
			for i = 1, 6 do
				local f = ShipSpriteData.damageFragments[i][0]
				expect(f.dy >= 0 and f.dy <= 2).to.equal(true)
			end
		end)

		it("lower-zone (J=1) Y offsets are all 3..4", function()
			for i = 1, 6 do
				local f = ShipSpriteData.damageFragments[i][1]
				expect(f.dy >= 3 and f.dy <= 4).to.equal(true)
			end
		end)

		it("multi-row fragment (idx 2 J=0) is 'fg' then 'mn' on consecutive rows", function()
			local f = ShipSpriteData.damageFragments[2][0]
			expect(#f.chars).to.equal(2)
			expect(f.chars[1]).to.equal("fg")
			expect(f.chars[2]).to.equal("mn")
		end)

		it("multi-row fragment (idx 4 J=1) is 'x' then 'z' on consecutive rows", function()
			local f = ShipSpriteData.damageFragments[4][1]
			expect(#f.chars).to.equal(2)
			expect(f.chars[1]).to.equal("x")
			expect(f.chars[2]).to.equal("z")
		end)
	end)

	describe("applyDamageFragment", function()
		it("overwrites the correct cells of a 5x7 grid", function()
			local grid = ShipSpriteData.newDamageGrid()
			ShipSpriteData.applyDamageFragment(grid, 1, 0)  -- "cde" at X+2, Y+0
			expect(grid[1][3]).to.equal("c")
			expect(grid[1][4]).to.equal("d")
			expect(grid[1][5]).to.equal("e")
		end)

		it("handles multi-row fragments (idx 2 J=0): 'fg' on row 1, 'mn' on row 2 at X+5", function()
			local grid = ShipSpriteData.newDamageGrid()
			ShipSpriteData.applyDamageFragment(grid, 2, 0)
			expect(grid[1][6]).to.equal("f")
			expect(grid[1][7]).to.equal("g")
			expect(grid[2][6]).to.equal("m")
			expect(grid[2][7]).to.equal("n")
		end)
	end)

	describe("renderRows", function()
		it("returns base sprite when grid is empty", function()
			local grid = ShipSpriteData.newDamageGrid()
			local rows = ShipSpriteData.renderRows(grid)
			expect(rows[1]).to.equal("ABCDEFG")
			expect(rows[5]).to.equal("YJJJJJZ")
		end)

		it("overlays damage chars on the base sprite", function()
			local grid = ShipSpriteData.newDamageGrid()
			ShipSpriteData.applyDamageFragment(grid, 1, 0)  -- "cde" at row 1 col 3..5
			local rows = ShipSpriteData.renderRows(grid)
			expect(rows[1]:sub(3, 5)).to.equal("cde")
			expect(rows[1]:sub(1, 2)).to.equal("AB")  -- untouched
			expect(rows[1]:sub(6, 7)).to.equal("FG")  -- untouched
		end)
	end)
end