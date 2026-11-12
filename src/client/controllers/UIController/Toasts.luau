-- Toasts: draws the notices Remotes.Notify sends. Shared/Notices owns what each kind means (its
-- colour, sound, lifetime, and whether it is a big moment); this module owns where they go.
--
-- Routine notices stack just above the hotbar (over the held item's name), newest nearest the
-- hotbar, at most MAX at once. A notice that repeats one still showing merges into it: the line
-- counts ("x3"), adds up its coins, and starts its time again, so a run of rewards or refusals
-- never pushes the others out. Big moments (a kind with a banner caption) show one at a time in the
-- banner at the top of the screen, queued. A notice whose Detail names a window opens it when
-- clicked. Each plays its kind's sound unless its Detail says the moment has its own.
--
-- Authored (tools/hud/notice_hud.luau; the place file only):
--   HUD.Toasts          the stack's holder; its UIListLayout stacks slots from the bottom. It keeps
--                       its authored size but follows HUD.ItemName, which InventoryScreen moves
--                       with the hotbar, so the stack never covers the slots at any screen size.
--   HUD.Banner          the banner's holder, top centre.
--   Assets.UI.Toast.Toast   a slot: an empty Frame whose height this module eases, holding `Card`.
--   Assets.UI.Toast.Banner  the banner's `Card`, which also has a `Title`.
--   Assets.UI.Toast.Icons   one Frame per kind, drawn in white; its parts take the kind's colour
--                           except those named "Cut".
-- A Card is a button with a `Border` stroke, a UIScale, and `Icon`, `Item` (a ViewportFrame, shown
-- instead of Icon for a notice about an item), `Text`, `Go` (shown when a click opens something)
-- and, in the stack, `Count`. Cards are authored at the reference screen's pixels and wrap long
-- text; a UIScale on the slot (or the banner holder) draws them at the HUD's zoom.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Inventory = require(ReplicatedStorage.Shared.Inventory)
local Notices = require(ReplicatedStorage.Shared.Notices)
local TextColors = require(ReplicatedStorage.Shared.TextColors)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Libraries = Players.LocalPlayer.PlayerScripts.Libraries
local Hud = require(Libraries.Hud)
local ItemIcon = require(Libraries.ItemIcon)
local Screens = require(Libraries.Screens)
local Sound = require(Libraries.Sound)
local UI = require(Libraries.UI)

local MAX = 4
-- Pixels at the reference size between the item name's top and the lowest toast, and between toasts.
local GAP = 4
local SPACING = 5
-- Banners waiting their turn; past this the oldest waiting one is dropped rather than shown stale.
local QUEUE = 5
-- Seconds within which the same sound is not played twice (a burst of merged refusals).
local SOUND_GAP = 0.15

local ENTER = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local MOVE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad)
local EVICT = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
local BUMP = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Every transparency under a card, as authored, so a card can fade out and in as one.
type Faded = { { node: Instance, property: string, shown: number } }
type Card = {
	card: GuiButton,
	scale: UIScale,
	-- The scale as authored, which the pop and the merge bump return to.
	rest: number,
	text: TextLabel,
	-- The widest the text may be before it wraps, in the card's own pixels.
	widest: number,
	item: ViewportFrame?,
	faded: Faded,
	release: () -> (),
}
type Entry = {
	slot: Frame,
	card: Card,
	count: TextLabel?,
	kind: Notices.Kind,
	template: string,
	amount: number?,
	repeats: number,
	-- Bumped whenever the lifetime restarts, so an older timer knows it was replaced.
	life: number,
	height: number,
	leaving: boolean,
}
type Pending = { message: string, kind: Notices.Kind, detail: Notices.Detail }

local Toasts = {}

local function still(): boolean
	return GuiService.ReducedMotionEnabled
end

local function collect(root: Instance): Faded
	local faded: Faded = {}
	local nodes = root:GetDescendants()
	table.insert(nodes, root)
	for _, node in nodes do
		if node:IsA("GuiObject") and node.BackgroundTransparency < 1 then
			table.insert(faded, { node = node, property = "BackgroundTransparency", shown = node.BackgroundTransparency })
		end
		if node:IsA("TextLabel") or node:IsA("TextButton") then
			table.insert(faded, { node = node, property = "TextTransparency", shown = node.TextTransparency })
		elseif node:IsA("ViewportFrame") then
			table.insert(faded, { node = node, property = "ImageTransparency", shown = node.ImageTransparency })
		elseif node:IsA("UIStroke") then
			table.insert(faded, { node = node, property = "Transparency", shown = node.Transparency })
		end
	end
	return faded
end

-- Fades a card to `hidden` (0 as authored, 1 gone), at once without `info`; returns one of the
-- tweens, to wait on, or nil when nothing is left to wait for.
local function fade(faded: Faded, hidden: number, info: TweenInfo?): Tween?
	local last: Tween? = nil
	for _, each in faded do
		local goal = each.shown + (1 - each.shown) * hidden
		if not info or still() then
			(each.node :: any)[each.property] = goal
		else
			local tween = TweenService:Create(each.node, info, { [each.property] = goal })
			tween:Play()
			last = tween
		end
	end
	return last
end

-- Sizes a card's text to its message: as wide as its longest line, wrapping at `widest`. A label
-- inside the card's automatic-size row neither wraps nor grows on its own (it stays one line), so
-- the text is measured in a copy of the label parented straight to the HUD, where nothing scales or
-- lays it out and TextBounds is the card's own pixels.
local function fit(text: TextLabel, widest: number, hud: ScreenGui)
	local probe = text:Clone()
	probe:ClearAllChildren()
	probe.TextTransparency = 1
	probe.AutomaticSize = Enum.AutomaticSize.None
	probe.TextWrapped = true
	probe.Position = UDim2.fromOffset(-4 * widest, 0)
	probe.Size = UDim2.fromOffset(widest, 1000)
	probe.Parent = hud
	local bounds = probe.TextBounds
	probe:Destroy()
	text.Size = UDim2.fromOffset(math.min(widest, math.ceil(bounds.X) + 2), math.ceil(bounds.Y))
end

local function paint(icon: Instance, color: Color3)
	for _, part in icon:GetDescendants() do
		if part.Name == "Cut" then
			continue
		end
		if part:IsA("GuiObject") then
			part.BackgroundColor3 = color
		elseif part:IsA("UIStroke") then
			part.Color = color
		end
	end
end

function Toasts.init(hud: ScreenGui)
	local holder = Hud.find(hud, "Toasts", "Frame")
	local bannerHolder = Hud.find(hud, "Banner", "Frame")
	local bannerZoom = Hud.find(hud, "Banner.UIScale", "UIScale")
	local itemName = Hud.find(hud, "ItemName", "TextLabel")
	local slotTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Toast.Toast", "Frame")
	local bannerTemplate = Hud.find(ReplicatedStorage, "Assets.UI.Toast.Banner", "GuiButton")
	local icons = Hud.find(ReplicatedStorage, "Assets.UI.Toast.Icons", "Folder")
	if not holder or not holder:IsA("Frame") or not itemName or not itemName:IsA("TextLabel") then
		return
	end
	if not bannerHolder or not bannerHolder:IsA("Frame") or not bannerZoom or not bannerZoom:IsA("UIScale") then
		return
	end
	if not slotTemplate or not slotTemplate:IsA("Frame") or not bannerTemplate or not bannerTemplate:IsA("GuiButton") then
		return
	end
	if not icons then
		return
	end
	holder.AnchorPoint = Vector2.new(0.5, 1)

	local active: { Entry } = {}
	-- Slots still on screen, leaving ones too, so a resize reaches them all.
	local slots: { [Frame]: UIScale } = {}
	local zoom = 1

	local function follow()
		zoom = Hud.zoom(hud.AbsoluteSize)
		local top = itemName.AbsolutePosition.Y - hud.AbsolutePosition.Y
		holder.Position = UDim2.new(0.5, 0, 0, top - GAP * zoom)
		bannerZoom.Scale = zoom
		for _, scale in slots do
			scale.Scale = zoom
		end
	end
	local followed = {
		itemName:GetPropertyChangedSignal("AbsolutePosition"):Connect(follow),
		hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow),
	}
	follow()

	local played: { [string]: number } = {}
	local function sound(kind: Notices.Kind, detail: Notices.Detail)
		local role = Notices.sound(kind)
		local now = os.clock()
		if not role or detail.quiet or now - (played[role] or -math.huge) < SOUND_GAP then
			return
		end
		played[role] = now
		Sound.play(role)
	end

	-- Fills a cloned card for one notice. `dismiss` is what a click does after opening the
	-- notice's window.
	local function fill(
		card: Instance,
		message: string,
		kind: Notices.Kind,
		detail: Notices.Detail,
		dismiss: () -> ()
	): Card?
		local text = card:FindFirstChild("Text", true)
		local scale = card:FindFirstChildOfClass("UIScale")
		if not card:IsA("GuiButton") or not text or not text:IsA("TextLabel") or not scale then
			warn(`HUD: {card:GetFullName()} must be a button with Text and a UIScale`)
			return nil
		end
		local limit = text:FindFirstChildOfClass("UISizeConstraint")
		local widest = if limit then limit.MaxSize.X else 340
		local color = Notices.color(kind)
		text.AutomaticSize = Enum.AutomaticSize.None
		text.TextWrapped = true
		-- The kind's colour stays the sentence's; amounts and item names in it take their own.
		text.RichText = true
		text.Text = TextColors.highlight(message)
		fit(text, widest, hud)
		text.TextColor3 = color
		local border = card:FindFirstChild("Border")
		if border and border:IsA("UIStroke") then
			border.Color = color
		end
		local brackets = card:FindFirstChild("Brackets")
		if brackets then
			paint(brackets, color)
		end
		local title = card:FindFirstChild("Title", true)
		if title and title:IsA("TextLabel") then
			title.Text = Notices.banner(kind) or ""
			title.TextColor3 = color
		end

		local icon = card:FindFirstChild("Icon", true)
		local viewport = card:FindFirstChild("Item", true)
		local shown: ViewportFrame? = nil
		if detail.item and Inventory.find(detail.item) and viewport and viewport:IsA("ViewportFrame") then
			ItemIcon.show(viewport, detail.item)
			viewport.Visible = true
			shown = viewport
			if icon and icon:IsA("GuiObject") then
				icon.Visible = false
			end
		elseif icon and icon:IsA("GuiObject") then
			local art = icons:FindFirstChild(kind)
			if art then
				local copy = art:Clone()
				paint(copy, color)
				copy.Parent = icon
			else
				icon.Visible = false
			end
		end

		local unbind: (() -> ())? = nil
		local go = card:FindFirstChild("Go", true)
		local window = detail.open
		if go and go:IsA("GuiObject") then
			go.Visible = window ~= nil
		end
		card.Active = window ~= nil
		card.Interactable = window ~= nil
		-- A notice comes and goes on its own; it must never take the gamepad's selection.
		card.Selectable = false
		if window then
			unbind = UI.bindButton(card, {
				hoverScale = 1.04,
				onActivate = function()
					Screens.open(window)
					dismiss()
				end,
			})
		end
		return {
			card = card,
			scale = scale,
			rest = scale.Scale,
			text = text,
			widest = widest,
			item = shown,
			faded = collect(card),
			release = function()
				if unbind then
					unbind()
				end
				if shown then
					ItemIcon.clear(shown)
				end
			end,
		}
	end

	local function appear(card: Card)
		if still() then
			return
		end
		fade(card.faded, 1)
		fade(card.faded, 0, MOVE)
		card.scale.Scale = card.rest * 0.9
		TweenService:Create(card.scale, ENTER, { Scale = card.rest }):Play()
	end

	------------------------------------------------------------------ the stack
	local order = 0

	-- Eases a slot to its card's height. The card's AbsoluteSize includes the HUD zoom and its own
	-- pop and hover scale, which are divided back out so those never move the stack.
	local function settle(entry: Entry)
		if entry.leaving then
			return
		end
		local drawn = zoom * entry.card.scale.Scale
		local height = if drawn > 0 then math.round(entry.card.card.AbsoluteSize.Y / drawn) + SPACING else 0
		if math.abs(height - entry.height) < 2 then
			return
		end
		entry.height = height
		local goal = UDim2.new(1, 0, 0, height)
		if still() then
			entry.slot.Size = goal
		else
			TweenService:Create(entry.slot, MOVE, { Size = goal }):Play()
		end
	end

	local function remove(entry: Entry, info: TweenInfo)
		if entry.leaving then
			return
		end
		entry.leaving = true
		local index = table.find(active, entry)
		if index then
			table.remove(active, index)
		end
		entry.card.card.Interactable = false
		local function gone()
			entry.card.release()
			slots[entry.slot] = nil
			entry.slot:Destroy()
		end
		local faded = fade(entry.card.faded, 1, info)
		if not faded then
			gone()
			return
		end
		-- The slot closes as the card fades, so the notices above glide down instead of dropping.
		local closing = TweenService:Create(entry.slot, MOVE, { Size = UDim2.new(1, 0, 0, 0) })
		faded.Completed:Once(function()
			closing:Play()
		end)
		closing.Completed:Once(gone)
	end

	local function expire(entry: Entry, seconds: number)
		entry.life += 1
		local life = entry.life
		task.delay(seconds, function()
			if entry.life == life then
				remove(entry, FADE)
			end
		end)
	end

	local function merge(entry: Entry, amount: number?)
		entry.repeats += 1
		local message = entry.template
		if entry.amount and amount then
			entry.amount += amount
			message = Notices.withAmount(entry.template, entry.amount)
			entry.card.text.Text = TextColors.highlight(message)
			fit(entry.card.text, entry.card.widest, hud)
		end
		if entry.count then
			entry.count.Text = `x{entry.repeats}`
			entry.count.Visible = true
		end
		if not still() then
			local card = entry.card
			local up = TweenService:Create(card.scale, BUMP, { Scale = card.rest * 1.07 })
			up.Completed:Once(function(state: Enum.PlaybackState)
				if state == Enum.PlaybackState.Completed then
					TweenService:Create(card.scale, BUMP, { Scale = card.rest }):Play()
				end
			end)
			up:Play()
		end
		expire(entry, Notices.lifetime(message, entry.kind))
	end

	local function stack(message: string, kind: Notices.Kind, detail: Notices.Detail)
		local template, amount = Notices.template(message)
		for _, entry in active do
			if entry.kind == kind and entry.template == template then
				merge(entry, amount)
				return
			end
		end
		local slot = slotTemplate:Clone()
		local card = slot:FindFirstChild("Card")
		local scale = slot:FindFirstChildOfClass("UIScale")
		local entry: Entry
		local filled = if card
			then fill(card, message, kind, detail, function()
				remove(entry, EVICT)
			end)
			else nil
		if not filled or not scale then
			slot:Destroy()
			return
		end
		local count = filled.card:FindFirstChild("Count", true)
		if count and count:IsA("TextLabel") then
			count.Visible = false
		end
		entry = {
			slot = slot,
			card = filled,
			count = if count and count:IsA("TextLabel") then count else nil,
			kind = kind,
			template = template,
			amount = amount,
			repeats = 1,
			life = 0,
			height = 0,
			leaving = false,
		}
		order += 1
		slot.LayoutOrder = order
		slot.Size = UDim2.new(1, 0, 0, 0)
		scale.Scale = zoom
		slots[slot] = scale
		slot.Visible = true
		slot.Parent = holder
		table.insert(active, entry)
		filled.card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			settle(entry)
		end)
		settle(entry)
		appear(filled)
		while #active > MAX do
			remove(active[1], EVICT)
		end
		expire(entry, Notices.lifetime(message, kind))
	end

	------------------------------------------------------------------ the banner
	local waiting: { Pending } = {}
	local showing: Pending? = nil
	local current: Card? = nil
	local turn = 0

	local advance: () -> ()

	local function leave()
		local card = current
		if not card then
			return
		end
		current = nil
		turn += 1
		card.card.Interactable = false
		local function gone()
			card.release()
			card.card:Destroy()
			showing = nil
			advance()
		end
		local faded = fade(card.faded, 1, FADE)
		if faded then
			faded.Completed:Once(gone)
		else
			gone()
		end
	end

	function advance()
		if showing or #waiting == 0 then
			return
		end
		local pending = table.remove(waiting, 1) :: Pending
		local card = bannerTemplate:Clone()
		local filled = fill(card, pending.message, pending.kind, pending.detail, leave)
		if not filled then
			card:Destroy()
			return
		end
		showing = pending
		current = filled
		card.Visible = true
		card.Parent = bannerHolder
		appear(filled)
		sound(pending.kind, pending.detail)
		turn += 1
		local mine = turn
		task.delay(Notices.lifetime(pending.message, pending.kind), function()
			if turn == mine then
				leave()
			end
		end)
	end

	local function announce(message: string, kind: Notices.Kind, detail: Notices.Detail)
		if showing and showing.message == message then
			return
		end
		for _, pending in waiting do
			if pending.message == message then
				return
			end
		end
		table.insert(waiting, { message = message, kind = kind, detail = detail })
		while #waiting > QUEUE do
			table.remove(waiting, 1)
		end
		advance()
	end

	local connection = Remotes.Notify.OnClientEvent:Connect(function(message: unknown, named: unknown, extra: unknown)
		if typeof(message) ~= "string" or message == "" then
			return
		end
		local kind: Notices.Kind = if Notices.isKind(named) then named :: Notices.Kind else Notices.DEFAULT
		local detail = Notices.detail(extra)
		if Notices.banner(kind) then
			announce(message, kind, detail)
		else
			stack(message, kind, detail)
			sound(kind, detail)
		end
	end)
	hud.Destroying:Once(function()
		connection:Disconnect()
		for _, each in followed do
			each:Disconnect()
		end
		for _, entry in active do
			entry.card.release()
		end
		if current then
			current.release()
		end
		table.clear(active)
		table.clear(waiting)
	end)
end
return Toasts
