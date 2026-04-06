local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BoxDrawing = require(ReplicatedStorage.Text.BoxDrawing)

return function()
	describe("BoxDrawing.topString", function()
		it("returns correct top border of width 5", function()
			local s = BoxDrawing.topString(5)
			expect(#s).to.equal(5)
			expect(string.byte(s, 1)).to.equal(187) -- top-left corner
			expect(string.byte(s, 5)).to.equal(189) -- top-right corner
			expect(string.byte(s, 2)).to.equal(141) -- top horizontal
			expect(string.byte(s, 3)).to.equal(141)
			expect(string.byte(s, 4)).to.equal(141)
		end)

		it("noLeftCorner replaces left corner with horizontal", function()
			local s = BoxDrawing.topString(5, { noLeftCorner = true })
			expect(string.byte(s, 1)).to.equal(141)
			expect(string.byte(s, 5)).to.equal(189)
		end)

		it("noRightCorner replaces right corner with horizontal", function()
			local s = BoxDrawing.topString(5, { noRightCorner = true })
			expect(string.byte(s, 1)).to.equal(187)
			expect(string.byte(s, 5)).to.equal(141)
		end)

		it("both noLeftCorner and noRightCorner gives all horizontals", function()
			local s = BoxDrawing.topString(5, { noLeftCorner = true, noRightCorner = true })
			for i = 1, 5 do
				expect(string.byte(s, i)).to.equal(141)
			end
		end)

		it("width 2 returns just two corner chars", function()
			local s = BoxDrawing.topString(2)
			expect(#s).to.equal(2)
			expect(string.byte(s, 1)).to.equal(187)
			expect(string.byte(s, 2)).to.equal(189)
		end)
	end)

	describe("BoxDrawing.bottomString", function()
		it("returns correct bottom border of width 5", function()
			local s = BoxDrawing.bottomString(5)
			expect(#s).to.equal(5)
			expect(string.byte(s, 1)).to.equal(156) -- bottom-left corner
			expect(string.byte(s, 5)).to.equal(158) -- bottom-right corner
			expect(string.byte(s, 2)).to.equal(154) -- bottom horizontal
			expect(string.byte(s, 3)).to.equal(154)
			expect(string.byte(s, 4)).to.equal(154)
		end)

		it("noLeftCorner replaces left corner with horizontal", function()
			local s = BoxDrawing.bottomString(5, { noLeftCorner = true })
			expect(string.byte(s, 1)).to.equal(154)
			expect(string.byte(s, 5)).to.equal(158)
		end)

		it("noRightCorner replaces right corner with horizontal", function()
			local s = BoxDrawing.bottomString(5, { noRightCorner = true })
			expect(string.byte(s, 1)).to.equal(156)
			expect(string.byte(s, 5)).to.equal(154)
		end)
	end)

	describe("BoxDrawing.dividerString", function()
		it("returns correct divider of width 5", function()
			local s = BoxDrawing.dividerString(5)
			expect(#s).to.equal(5)
			expect(string.byte(s, 1)).to.equal(136) -- divider left
			expect(string.byte(s, 5)).to.equal(137) -- divider right
			expect(string.byte(s, 2)).to.equal(157) -- divider horizontal
			expect(string.byte(s, 3)).to.equal(157)
			expect(string.byte(s, 4)).to.equal(157)
		end)

		it("width 2 returns just two junction chars", function()
			local s = BoxDrawing.dividerString(2)
			expect(#s).to.equal(2)
			expect(string.byte(s, 1)).to.equal(136)
			expect(string.byte(s, 2)).to.equal(137)
		end)
	end)

	describe("BoxDrawing.rowBorderString", function()
		it("returns correct row border of width 5", function()
			local s = BoxDrawing.rowBorderString(5)
			expect(#s).to.equal(5)
			expect(string.byte(s, 1)).to.equal(129) -- vertical bar
			expect(string.byte(s, 5)).to.equal(129) -- vertical bar
			expect(string.byte(s, 2)).to.equal(32)  -- space
			expect(string.byte(s, 3)).to.equal(32)
			expect(string.byte(s, 4)).to.equal(32)
		end)
	end)

	describe("BoxDrawing.boxTop", function()
		it("returns segmented line with TaipanThickFont", function()
			local color = Color3.fromRGB(200, 180, 80)
			local line = BoxDrawing.boxTop(10, color)
			expect(line.segments).to.be.ok()
			expect(#line.segments).to.equal(1)
			expect(line.segments[1].font).to.equal("TaipanThickFont")
			expect(line.segments[1].color).to.equal(color)
			expect(#line.segments[1].text).to.equal(10)
			expect(string.byte(line.segments[1].text, 1)).to.equal(187)
			expect(string.byte(line.segments[1].text, 10)).to.equal(189)
		end)

		it("passes opts through correctly", function()
			local line = BoxDrawing.boxTop(10, Color3.new(1,1,1), { noLeftCorner = true })
			expect(string.byte(line.segments[1].text, 1)).to.equal(141)
			expect(string.byte(line.segments[1].text, 10)).to.equal(189)
		end)
	end)

	describe("BoxDrawing.boxBottom", function()
		it("returns segmented line with correct chars", function()
			local color = Color3.fromRGB(200, 180, 80)
			local line = BoxDrawing.boxBottom(10, color)
			expect(#line.segments).to.equal(1)
			expect(line.segments[1].font).to.equal("TaipanThickFont")
			expect(string.byte(line.segments[1].text, 1)).to.equal(156)
			expect(string.byte(line.segments[1].text, 10)).to.equal(158)
		end)
	end)

	describe("BoxDrawing.boxDivider", function()
		it("returns segmented line with divider chars", function()
			local color = Color3.fromRGB(200, 180, 80)
			local line = BoxDrawing.boxDivider(10, color)
			expect(#line.segments).to.equal(1)
			expect(line.segments[1].font).to.equal("TaipanThickFont")
			expect(string.byte(line.segments[1].text, 1)).to.equal(136)
			expect(string.byte(line.segments[1].text, 10)).to.equal(137)
		end)
	end)

	describe("BoxDrawing.boxRow", function()
		it("returns 3 segments with correct structure", function()
			local bc = Color3.fromRGB(200, 180, 80)
			local tc = Color3.fromRGB(140, 200, 80)
			local line = BoxDrawing.boxRow(10, "HELLO", bc, tc)
			expect(#line.segments).to.equal(3)
			-- left vertical bar
			expect(string.byte(line.segments[1].text, 1)).to.equal(129)
			expect(line.segments[1].font).to.equal("TaipanThickFont")
			expect(line.segments[1].color).to.equal(bc)
			-- content (padded to 8 chars)
			expect(#line.segments[2].text).to.equal(8)
			expect(line.segments[2].text:sub(1, 5)).to.equal("HELLO")
			expect(line.segments[2].color).to.equal(tc)
			expect(line.segments[2].font).to.equal(nil)
			-- right vertical bar
			expect(string.byte(line.segments[3].text, 1)).to.equal(129)
			expect(line.segments[3].font).to.equal("TaipanThickFont")
		end)

		it("truncates long content", function()
			local line = BoxDrawing.boxRow(10, "TOOLONG!!", Color3.new(1,1,1))
			expect(#line.segments[2].text).to.equal(8)
			expect(line.segments[2].text).to.equal("TOOLONG!")
		end)

		it("pads empty content with spaces", function()
			local line = BoxDrawing.boxRow(10, "", Color3.new(1,1,1))
			expect(#line.segments[2].text).to.equal(8)
			expect(line.segments[2].text).to.equal(string.rep(" ", 8))
		end)

		it("uses borderColor as contentColor default", function()
			local bc = Color3.fromRGB(200, 180, 80)
			local line = BoxDrawing.boxRow(10, "X", bc)
			expect(line.segments[2].color).to.equal(bc)
		end)
	end)
end