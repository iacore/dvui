const std = @import("std");
const dvui = @import("dvui.zig");

const Color = dvui.Color;
const Font = dvui.Font;
const Rect = dvui.Rect;
const Corner = dvui.Corner;
const CornerRect = dvui.CornerRect;
const Size = dvui.Size;
const Theme = dvui.Theme;
const Ninepatch = dvui.Ninepatch;

const Profiling = @import("Profiling.zig");

/// One layer of widget option values.
///
/// A layer holds only what its author set: every field is optional, and the
/// getters resolve a null through the theme or through fixed defaults.  The
/// design is that a layer stays a layer -- a widget reads through the layer it
/// was given -- so no new code combines two layers.  `override` survives only
/// because 213 call sites still use it; it flattens two layers into one and
/// MUST be migrated away, not extended.
pub const ContextLayer = struct {
    /// Read volume for the Context-layer study: how many times each resolution path
    /// runs per frame while `dvui.profiling.recording` is on. Counting reads is what
    /// decides whether a layered `Context` handle (fewer writes, more reads) can pay;
    /// the counters are off in normal builds because the flag is off.
    pub const ReadStats = struct {
        getters: u64 = 0,
        colors: u64 = 0,
        fonts: u64 = 0,
        sizes: u64 = 0,
        overrides: u64 = 0,
        copies: u64 = 0,
    };
    pub var read_stats: ReadStats = .{};

    inline fn noted(comptime field: enum { getters, colors, fonts, sizes, overrides, copies }) void {
        // Compiled out of ordinary builds: `-Dprofiling` is what turns the counters
        // on, so a normal build pays nothing for them.
        if (comptime !Profiling.compile_time) return;
        if (!Profiling.recording) return;
        switch (field) {
            inline else => |f| @field(read_stats, @tagName(f)) += 1,
        }
    }

    /// Which fields a stored layer sets: one bit per field, in `Tag` order.
    pub const Mask = u64;

    /// Every field of a layer, in the order the bitset and the value cells use.
    pub const Tag = enum(u6) {
        id_extra,
        tag,
        name,
        role,
        label,
        data_out,
        rect,
        expand,
        gravity_x,
        gravity_y,
        tab_index,
        color_fill,
        color_fill_hover,
        color_fill_press,
        color_text,
        color_text_hover,
        color_text_press,
        color_border,
        ninepatch_fill,
        ninepatch_hover,
        ninepatch_press,
        style,
        theme,
        font,
        rotation,
        margin,
        border,
        padding,
        corners,
        min_size_content,
        max_size_content,
        background,
        box_shadow,
    };

    /// The type a field is stored as: the field's own type, without the
    /// optional that records "no layer set this".
    pub fn Payload(comptime field: []const u8) type {
        const T = @FieldType(ContextLayer, field);
        return if (@typeInfo(T) == .optional) @typeInfo(T).optional.child else T;
    }

    /// Alignment a stored value needs: the widest alignment any field asks for.
    ///
    /// A stored value is read back as a `*const T` into the cell holding it, so
    /// the cell's address must satisfy `@alignOf(T)`.  The cells live in a byte
    /// buffer allocated at this alignment and `cell_size` is a multiple of it,
    /// so every cell satisfies every field's alignment.
    pub const cell_align = blk: {
        var widest: usize = 1;
        for (@typeInfo(ContextLayer).@"struct".field_names) |f_name| {
            if (std.mem.eql(u8, f_name, "_base")) continue;
            widest = @max(widest, @alignOf(Payload(f_name)));
        }
        break :blk widest;
    };

    /// Bytes one stored value occupies: the widest field rounded up to
    /// `cell_align`, so every field's value fits a cell aligned.
    pub const cell_size = blk: {
        var biggest: usize = 1;
        for (@typeInfo(ContextLayer).@"struct".field_names) |f_name| {
            if (std.mem.eql(u8, f_name, "_base")) continue;
            biggest = @max(biggest, @sizeOf(Payload(f_name)));
        }
        break :blk std.mem.alignForward(usize, biggest, cell_align);
    };

    /// Mixed into widget id. Use when @src() is not unique (like in a loop).
    id_extra: ?usize = null,

    /// String for programmatically interacting with widgets, like in tests.
    tag: ?[]const u8 = null,

    /// Name for debugging, says what kind of widget ("Button" or "Text Entry").
    name: ?[]const u8 = null,

    /// Accessibility role (.BUTTON or .TEXT_INPUT), says what kind of widget.
    role: ?dvui.AccessKit.Role = null,

    /// Accessibility label, either another widget or text.
    label: ?LabelOpts = null,

    /// Pass a pointer to get a copy of the widget's `data` when `register` was
    /// called.  Useful for getting id/rect info out of a higher-level function.
    data_out: ?*dvui.WidgetData = null,

    /// Specific placement within parent.  Null is normal, meaning parent picks a
    /// rect for the child widget.
    ///
    /// If non-null, child widget is choosing its own place, meaning its not being
    /// placed normally.  w and h will still be expanded if expand is set. Example
    /// is the demo Scroll Canvas, where user code chooses widget placement.
    ///
    /// If non-null, should not call rectFor or minSizeForChild.
    rect: ?Rect = null,

    // default is .none
    expand: ?Expand = null,

    // [0, 1] default is 0 (left)
    gravity_x: ?f32 = null,

    // [0, 1] default is 0 (top)
    gravity_y: ?f32 = null,

    /// Specify focus order within the current TabIndexGroup.
    /// * lower numbers first
    /// * null means highest possible
    /// * same tab_index go in processed order
    /// * 0 disables (cannot focus via keyboard navigation)
    tab_index: ?u16 = null,

    // Used to override the style/theme. `color_fill*`/`color_text*`/`color_border`
    // can each be a flat color or a gradient (see `ColorOrGradient`).
    color_fill: ?ColorOrGradient = null,
    color_fill_hover: ?ColorOrGradient = null,
    color_fill_press: ?ColorOrGradient = null,
    color_text: ?ColorOrGradient = null,
    color_text_hover: ?ColorOrGradient = null,
    color_text_press: ?ColorOrGradient = null,
    color_border: ?ColorOrGradient = null,

    ninepatch_fill: ?*const Ninepatch = null,
    ninepatch_hover: ?*const Ninepatch = null,
    ninepatch_press: ?*const Ninepatch = null,

    // If a color above is null, source it from this style (if null, .content) in the theme.
    style: ?Theme.Style.Name = null,

    // If not null, source colors from here instead of the global theme.
    theme: ?*const Theme = null,

    // Use specified font
    font: ?Font = null,

    // only used for icons/images, rotates around center, radians clockwise
    rotation: ?f32 = null,

    // For the rest of these fields, if null, each widget uses its defaults

    // x left, y top, w right, h bottom
    margin: ?Rect = null,
    border: ?Rect = null,
    padding: ?Rect = null,

    corners: ?CornerRect = null,

    /// Widget min size will be at least this, unless max_size_content is smaller.
    ///
    /// padding/border/margin will be added to this.
    min_size_content: ?Size = null,

    /// Widget min size can't exceed this, even if min_size_content is larger.
    ///
    /// Use when a child textLayout or scrollArea is making the parent too big.
    ///
    /// padding/border/margin will be added to this.
    max_size_content: ?MaxSize = null,

    // whether to fill the background
    background: ?bool = null,

    /// Render a box shadow in `WidgetData.borderAndBackground`.
    box_shadow: ?BoxShadow = null,

    /// Index of the layer this one resolves through, in the current window's
    /// `ctx_layers` list.  A layer set by `override` keeps only its own fields
    /// and points at the layer it was applied to; every getter walks this chain
    /// until a field is set.  `null` means this layer is the root of its chain.
    _base: ?u32 = null,

    const ColorOrGradient = dvui.ColorOrGradient;

    pub const LabelOpts = union(enum) {
        /// Use the label from a different widget.  This is preferred if there is a
        /// visible widget that labels this one.
        by_id: dvui.Id,

        /// Use this label for a different widget.
        for_id: dvui.Id,

        /// Use the previous or next label widget to label this widget.
        label_widget: enum { prev, next },

        /// Use this text as the label.  Prefer using .by if possible - .text is
        /// for cases where there is no visible label (like an icon or image).
        text: []const u8,
    };

    pub const Expand = enum {
        none,
        horizontal,
        vertical,
        both,

        /// Expand while keeping aspect ratio.
        ratio,

        pub fn isHorizontal(self: Expand) bool {
            return (self == .horizontal or self == .both);
        }

        pub fn isVertical(self: Expand) bool {
            return (self == .vertical or self == .both);
        }

        pub fn fromDirection(dir: dvui.enums.Direction) Expand {
            return switch (dir) {
                .horizontal => .horizontal,
                .vertical => .vertical,
            };
        }
    };

    pub const Gravity = struct {
        // wraps ContextLayer.gravity_x and ContextLayer.gravity_y
        x: f32,
        y: f32,
    };

    pub const MaxSize = struct {
        w: f32,
        h: f32,

        pub const zero: MaxSize = .{ .w = 0, .h = 0 };

        pub fn width(w: f32) MaxSize {
            return .{ .w = w, .h = dvui.max_float_safe };
        }

        pub fn height(h: f32) MaxSize {
            return .{ .w = dvui.max_float_safe, .h = h };
        }

        pub fn size(s: Size) MaxSize {
            return .{ .w = s.w, .h = s.h };
        }

        pub fn all(v: f32) MaxSize {
            return .{ .w = v, .h = v };
        }

        /// Size of "M" characters in current theme body font.
        pub fn sizeM(wide: f32, tall: f32) MaxSize {
            return .size(dvui.Font.theme(.body).sizeM(wide, tall));
        }

        pub fn cast(anysize: anytype) MaxSize {
            return .{ .w = anysize.w, .h = anysize.h };
        }
    };

    pub const BoxShadow = struct {
        /// Color of shadow
        color: Color = .black,

        // if null uses ContextLayer.corners
        corners: ?CornerRect = null,

        /// Shrink the shadow on all sides (before fade)
        shrink: f32 = 0,

        /// Offset down/right
        offset: dvui.Point = .{ .x = 1, .y = 1 },

        /// Extend the size of the transition to transparent at the edges
        fade: f32 = 2,

        /// Additional alpha multiply factor
        alpha: f32 = 0.5,
    };

    /// The value of `field` from the first layer in this chain that sets it.
    ///
    /// The layer's own fields are inline; the layers it inherits from are only
    /// stored, as a bitset of which fields they set plus those fields' values,
    /// so a chain costs one value per field an author wrote rather than a full
    /// layer of nulls.
    pub fn get(self: *const ContextLayer, comptime field: []const u8) @FieldType(ContextLayer, field) {
        if (@field(self, field)) |v| return v;

        const items = dvui.currentWindow().ctx_layers.items;
        var idx = self._base;
        while (idx) |at| {
            const slot = items[at];
            if (slot.cellOf(field)) |cell| return slot.read(field, cell);
            idx = slot.base;
        }
        return null;
    }

    /// Whether any layer in this chain sets `field`.
    pub fn has(self: *const ContextLayer, comptime field: []const u8) bool {
        return self.get(field) != null;
    }

    /// Whether the resolved role is `role`.  False when no layer sets a role.
    pub fn roleIs(self: *const ContextLayer, role: dvui.AccessKit.Role) bool {
        const r = self.get("role") orelse return false;
        return r == role;
    }

    /// One stored layer's answer: which fields it set, and those fields' values.
    ///
    /// Availability is a bitset, not a per-field optional: for a field present
    /// in `mask`, its value sits in cell `@popCount(mask & (bit - 1))` of
    /// `values`.  `cellOf` finds that cell by walking the bits below with
    /// `@ctz`, so a read costs one test per set field, and the bytes after the
    /// last set field are never allocated at all.
    pub const Slot = struct {
        base: ?u32 = null,
        mask: Mask = 0,
        /// `@popCount(mask)` cells of `cell_size` bytes, in field order.
        values: []align(cell_align) const u8 = &.{},

        /// Which cell of `values` holds `field`, or null when this layer does
        /// not set it.
        pub inline fn cellOf(slot: Slot, comptime field: []const u8) ?usize {
            const target = @intFromEnum(@field(Tag, field));
            if (slot.mask & (@as(Mask, 1) << @intCast(target)) == 0) return null;

            var bits = slot.mask;
            var cell: usize = 0;
            while (bits != 0) : (bits &= bits - 1) {
                if (@ctz(bits) == target) return cell;
                cell += 1;
            }
            return null;
        }

        /// The value stored in `cell` for `field`.
        ///
        /// The cell is read as `T` from an address `cell_size`-strided from a
        /// buffer allocated at `cell_align`, so the address meets `@alignOf(T)`.
        pub inline fn read(slot: Slot, comptime field: []const u8, cell: usize) Payload(field) {
            const T = Payload(field);
            const bytes: *const [@sizeOf(T)]u8 = @ptrCast(&slot.values[cell * cell_size]);
            return std.mem.bytesToValue(T, bytes);
        }
    };

    /// How many values this layer stores.
    pub inline fn valueCount(self: *const ContextLayer) usize {
        var n: usize = 0;
        inline for (@typeInfo(ContextLayer).@"struct".field_names) |f_name| {
            if (comptime !std.mem.eql(u8, f_name, "_base")) {
                if (@field(self, f_name) != null) n += 1;
            }
        }
        return n;
    }

    /// Writes this layer's set fields into `out` (which needs `valueCount` cells
    /// of room) and returns the bitset naming them.
    pub inline fn writeLayer(self: *const ContextLayer, out: []align(cell_align) u8) Mask {
        var mask: Mask = 0;
        var cell: usize = 0;
        inline for (@typeInfo(ContextLayer).@"struct".field_names) |f_name| {
            if (comptime !std.mem.eql(u8, f_name, "_base")) {
                if (@field(self, f_name)) |v| {
                    const T = Payload(f_name);
                    const ptr: *T = @ptrCast(@alignCast(&out[cell * cell_size]));
                    ptr.* = v;
                    mask |= @as(Mask, 1) << @intCast(@intFromEnum(@field(Tag, f_name)));
                    cell += 1;
                }
            }
        }
        return mask;
    }

    /// All the colors you can ask ContextLayer for
    pub const ColorAsk = enum {
        text,
        text_hover,
        text_press,
        fill,
        fill_hover,
        fill_press,
        border,
    };

    /// Get a color (or gradient) from this ContextLayer or fallback to theme colors.
    /// Hover/press auto-adjustment (see `Theme.adjustColorForState`) only
    /// applies when the fallback source is a flat color -- gradients don't get
    /// an automatic hover/press adjustment.
    ///
    /// Only valid between `Window.begin`and `Window.end`.
    pub fn color(self: *const ContextLayer, ask: ColorAsk) ColorOrGradient {
        noted(.colors);
        return switch (ask) {
            .border => self.get("color_border"),
            .fill => self.get("color_fill"),
            .fill_hover => self.get("color_fill_hover") orelse if (self.get("color_fill")) |cog| adjustColorOrGradientForState(self, cog, ask) else null,
            .fill_press => self.get("color_fill_press") orelse if (self.get("color_fill")) |cog| adjustColorOrGradientForState(self, cog, ask) else null,
            .text => self.get("color_text"),
            .text_hover => self.get("color_text_hover") orelse if (self.get("color_text")) |cog| adjustColorOrGradientForState(self, cog, ask) else null,
            .text_press => self.get("color_text_press") orelse if (self.get("color_text")) |cog| adjustColorOrGradientForState(self, cog, ask) else null,
        } orelse ColorOrGradient{ .color = self.themeGet().color(self.styleGet(), ask) };
    }

    fn adjustColorOrGradientForState(self: *const ContextLayer, cog: ColorOrGradient, ask: ColorAsk) ColorOrGradient {
        return switch (cog) {
            .color => |c| .{ .color = self.themeGet().adjustColorForState(c, ask) },
            .gradient => cog,
        };
    }

    /// Kinds of Ninepatch you can ask ContextLayer for.
    pub const NinepatchAsk = enum {
        fill,
        hover,
        press,
    };

    pub fn ninepatch(self: *const ContextLayer, ask: NinepatchAsk) ?*const Ninepatch {
        noted(.getters);
        const np_opt = switch (ask) {
            .fill => self.get("ninepatch_fill"),
            .hover => self.get("ninepatch_hover") orelse self.get("ninepatch_fill"),
            .press => self.get("ninepatch_press") orelse self.get("ninepatch_fill"),
        };
        if (np_opt) |np| return np;

        return self.themeGet().ninepatch(self.styleGet(), ask);
    }

    pub fn fontGet(self: *const ContextLayer) Font {
        noted(.fonts);
        return self.get("font") orelse self.themeGet().font_body;
    }

    pub fn idExtra(self: *const ContextLayer) usize {
        noted(.getters);
        return self.get("id_extra") orelse (Context_Prototype{}).id_extra;
    }

    pub fn expandGet(self: *const ContextLayer) Expand {
        noted(.getters);
        return self.get("expand") orelse (Context_Prototype{}).expand;
    }

    pub fn gravityGet(self: *const ContextLayer) Gravity {
        noted(.getters);
        return .{ .x = self.get("gravity_x") orelse (Context_Prototype{}).gravity_x, .y = self.get("gravity_y") orelse (Context_Prototype{}).gravity_y };
    }

    pub fn marginGet(self: *const ContextLayer) Rect {
        noted(.getters);
        return self.get("margin") orelse (Context_Prototype{}).margin;
    }

    pub fn borderGet(self: *const ContextLayer) Rect {
        noted(.getters);
        return self.get("border") orelse (Context_Prototype{}).border;
    }

    pub fn backgroundGet(self: *const ContextLayer) bool {
        noted(.getters);
        return self.get("background") orelse (Context_Prototype{}).background;
    }

    pub fn paddingGet(self: *const ContextLayer) Rect {
        noted(.getters);
        return self.get("padding") orelse (Context_Prototype{}).padding;
    }

    pub fn cornersGet(self: *const ContextLayer) CornerRect {
        noted(.getters);
        return (self.get("corners") orelse (Context_Prototype{}).corners).finalize(self.themeGet());
    }

    /// Combines min_size_content and max_size_content, adds margin/border/padding.
    pub fn min_sizeGet(self: *const ContextLayer) Size {
        noted(.sizes);
        return self.padSize(self.min_size_contentGet().min(self.max_size_contentGet()));
    }

    pub fn min_size_contentGet(self: *const ContextLayer) Size {
        noted(.sizes);
        return self.get("min_size_content") orelse (Context_Prototype{}).min_size_content;
    }

    pub fn max_sizeGet(self: *const ContextLayer) Size {
        noted(.sizes);
        return self.padSize(self.max_size_contentGet());
    }

    pub fn max_size_contentGet(self: *const ContextLayer) Size {
        noted(.sizes);
        const msc = self.get("max_size_content") orelse (Context_Prototype{}).max_size_content;
        return .{ .w = msc.w, .h = msc.h };
    }

    pub fn rotationGet(self: *const ContextLayer) f32 {
        noted(.getters);
        return self.get("rotation") orelse (Context_Prototype{}).rotation;
    }

    pub fn styleGet(self: *const ContextLayer) Theme.Style.Name {
        noted(.getters);
        return self.get("style") orelse (Context_Prototype{}).style;
    }

    pub fn themeGet(self: *const ContextLayer) *const Theme {
        noted(.getters);
        return self.get("theme") orelse &dvui.currentWindow().theme;
    }


    /// Keeps only the fonts and colors. Intended for stuff like buttons passing
    /// down options to internal widgets.
    pub fn styleOnly(self: *const ContextLayer) ContextLayer {
        noted(.copies);
        return .{
            .style = self.get("style"),
            .theme = self.get("theme"),

            .color_fill = self.get("color_fill"),
            .color_fill_hover = self.get("color_fill_hover"),
            .color_fill_press = self.get("color_fill_press"),
            .color_text = self.get("color_text"),
            .color_text_hover = self.get("color_text_hover"),
            .color_text_press = self.get("color_text_press"),
            .color_border = self.get("color_border"),

            .font = self.get("font"),
        };
    }

    // Used in compound widgets to strip out the styling that should only apply to
    // the outermost container widget.  Also zero out
    // margin/border/padding/background because those are usually for freestanding
    // widgets.
    //
    // For example, with a button
    // (container with label) the container uses:
    // - rect
    // - min_size_content
    // - max_size_content
    // - margin
    // - border
    // - background
    // - padding
    // - corners
    // - expand
    // - gravity
    // while the label uses:
    // - fonts
    // - colors
    // - and we don't want the normal label margin/padding
    pub fn strip(self: *const ContextLayer) ContextLayer {
        noted(.copies);
        return ContextLayer{
            // reset to defaults of internal widgets
            .id_extra = null,
            .tag = null,
            .name = null,
            .data_out = null,
            .rect = null,
            .min_size_content = null,
            .max_size_content = null,
            .expand = null,
            .gravity_x = null,
            .gravity_y = null,
            .tab_index = null,
            .box_shadow = null,
            .role = null,
            .label = null,

            // ignore defaults of internal widgets
            .margin = Rect{},
            .border = Rect{},
            .padding = Rect{},
            .corners = CornerRect{},
            .background = false,
            .ninepatch_fill = &Ninepatch.none,
            .ninepatch_hover = &Ninepatch.none,
            .ninepatch_press = &Ninepatch.none,

            // keep the rest
            .style = self.get("style"),
            .theme = self.get("theme"),
            .color_fill = self.get("color_fill"),
            .color_fill_hover = self.get("color_fill_hover"),
            .color_fill_press = self.get("color_fill_press"),
            .color_text = self.get("color_text"),
            .color_text_hover = self.get("color_text_hover"),
            .color_text_press = self.get("color_text_press"),
            .color_border = self.get("color_border"),

            .font = self.get("font"),

            .rotation = self.get("rotation"),
        };
    }

    /// Applies `over` on top of this layer and returns the combination.
    ///
    /// Read order is `over`'s own fields, then the chain `over` already had,
    /// then this layer and its chain -- what a flat merge produces.  Nothing is
    /// merged: this layer is stored as the patches it sets and `over`'s chain is
    /// re-rooted onto it, so a combination costs one patch per field actually
    /// written.  `flat` materializes a chain when a value has to outlive the
    /// frame.
    pub fn override(self: *const ContextLayer, over: ContextLayer) ContextLayer {
        noted(.overrides);
        const cw = dvui.currentWindow();
        const self_slot = cw.ctxLayerPushLayer(self.*) orelse return self.overrideFlat(over);

        var ret = over;
        if (over._base) |over_base| {
            ret._base = cw.ctxLayerRelink(over_base, self_slot) orelse return self.overrideFlat(over);
        } else {
            ret._base = self_slot;
        }
        return ret;
    }

    /// `override` without the layer list: one merged value, no chain.
    pub fn overrideFlat(self: *const ContextLayer, over: ContextLayer) ContextLayer {
        noted(.copies);
        var ret = self.flat();
        const src = if (over._base != null) over.flat() else over;

        inline for (@typeInfo(ContextLayer).@"struct".field_names) |f_name| {
            if (comptime !std.mem.eql(u8, f_name, "_base")) {
                if (@field(src, f_name)) |fval| {
                    @field(ret, f_name) = fval;
                }
            }
        }

        return ret;
    }

    /// This layer with its chain flattened and `_base` cleared, for storing
    /// past the frame the chain was built in.
    pub fn flat(self: *const ContextLayer) ContextLayer {
        noted(.copies);
        var ret: ContextLayer = .{};
        inline for (@typeInfo(ContextLayer).@"struct".field_names) |f_name| {
            if (comptime !std.mem.eql(u8, f_name, "_base")) {
                @field(ret, f_name) = self.get(f_name);
            }
        }
        return ret;
    }

    pub fn min_sizeM(self: *const ContextLayer, wide: f32, tall: f32) ContextLayer {
        return self.override(.{ .min_size_content = self.fontGet().sizeM(wide, tall) });
    }

    pub fn max_sizeM(self: *const ContextLayer, wide: f32, tall: f32) ContextLayer {
        return self.override(.{ .max_size_content = .size(self.fontGet().sizeM(wide, tall)) });
    }

    pub fn padSize(self: *const ContextLayer, s: Size) Size {
        return s.pad(self.paddingGet()).pad(self.borderGet()).pad(self.marginGet());
    }

    /// Hashes all the values of the options
    ///
    /// Only useful to check exact equality between two `ContextLayer`
    pub fn hash(self: *const ContextLayer) u64 {
        noted(.copies);
        const asBytes = std.mem.asBytes;
        var hasher = dvui.fnv.init();

        hasher.update(asBytes(&self.min_size_contentGet()));
        hasher.update(asBytes(&self.max_size_contentGet()));
        if (self.get("rect")) |rect| hasher.update(asBytes(&rect));

        hasher.update(asBytes(&self.borderGet()));
        hasher.update(asBytes(&self.marginGet()));
        hasher.update(asBytes(&self.paddingGet()));

        hasher.update(asBytes(&self.cornersGet()));
        hasher.update(asBytes(&self.gravityGet()));
        hasher.update(asBytes(&self.expandGet()));
        hasher.update(asBytes(&self.rotationGet()));
        hasher.update(asBytes(&self.backgroundGet()));

        hasher.update(asBytes(&self.styleGet()));
        // FIXME: Should hash the theme fields here in a consistent way
        // hasher.update(asBytes(self.themeGet()));

        if (self.get("color_fill")) |col| hasher.update(asBytes(&col));
        if (self.get("color_fill_hover")) |col| hasher.update(asBytes(&col));
        if (self.get("color_fill_press")) |col| hasher.update(asBytes(&col));
        if (self.get("color_text")) |col| hasher.update(asBytes(&col));
        if (self.get("color_text_hover")) |col| hasher.update(asBytes(&col));
        if (self.get("color_text_press")) |col| hasher.update(asBytes(&col));
        if (self.get("color_border")) |col| hasher.update(asBytes(&col));

        const font = self.fontGet();
        hasher.update(asBytes(&font.hash()));

        if (self.get("tab_index")) |ti| hasher.update(asBytes(&ti));
        hasher.update(asBytes(&self.idExtra()));
        if (self.get("tag")) |tag| hasher.update(tag);
        if (self.get("name")) |name| hasher.update(name);

        return hasher.final();
    }

    //pub fn format(self: *const ContextLayer, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    //    try std.fmt.format(writer, "ContextLayer{{ .background = {?}, .color_style = {?} }}", .{ self.background, self.color_style });
    //}
};

test {
    @import("std").testing.refAllDecls(ContextLayer);
}

test "override resolves through the base layer" {
    var t = try dvui.testing.init(.{ .window_size = .{ .w = 100, .h = 100 } });
    defer t.deinit();

    const frame = struct {
        fn frame() !dvui.App.Result {
            const base: dvui.ContextLayer = .{
                .id_extra = 7,
                .padding = .all(3),
                .expand = .horizontal,
                .color_text = .{ .color = .red },
                .font = dvui.Font.theme(.body),
                .min_size_content = .{ .w = 5, .h = 6 },
                .tab_index = 4,
            };
            const overridden = base.override(.{ .name = "x", .background = true });
            if (overridden.idExtra() != 7) return error.BadIdExtra;
            if (overridden.paddingGet().x != 3) return error.BadPadding;
            if (overridden.get("name") == null) return error.BadName;
            if (overridden.expandGet() != .horizontal) return error.BadExpand;
            if (overridden.get("color_text") == null) return error.BadColor;
            if (overridden.get("font") == null) return error.BadFont;
            if (overridden.min_size_contentGet().w != 5) return error.BadMinSize;
            if (overridden.get("tab_index") != 4) return error.BadTabIndex;
            if (!overridden.backgroundGet()) return error.BadBackground;

            const flat = overridden.flat();
            if (flat.idExtra() != 7) return error.FlatLostIdExtra;
            if (flat.get("name") == null) return error.FlatLostName;
            if (overridden.hash() != flat.hash()) return error.HashDiffers;

            const cleared = base.override(.{ .background = true });
            if (cleared.idExtra() != 7) return error.ClearedLostIdExtra;
            if (!cleared.backgroundGet()) return error.ClearedLostBackground;
            return .ok;
        }
    }.frame;

    _ = try dvui.testing.step(frame);
}

/// The schema of one layer: every field, with the value it resolves to when no
/// layer sets it.
///
/// Nothing reads this struct as a value.  The sparse `Patch` form is generated
/// from it, the getters take their fallbacks from it, and a test keeps
/// `ContextLayer`'s fields in step with it, so a field is declared once and its
/// default sits next to it.  A field whose empty-chain answer needs the window
/// (the theme, the body font, theme colours) defaults to null and is resolved by
/// its getter; everything else defaults to the answer itself.
pub const Context_Prototype = struct {
    id_extra: usize = 0,
    tag: ?[]const u8 = null,
    name: ?[]const u8 = null,
    role: ?dvui.AccessKit.Role = null,
    label: ?ContextLayer.LabelOpts = null,
    data_out: ?*dvui.WidgetData = null,
    rect: ?Rect = null,
    expand: ContextLayer.Expand = .none,
    gravity_x: f32 = 0,
    gravity_y: f32 = 0,
    tab_index: ?u16 = null,
    color_fill: ?dvui.ColorOrGradient = null,
    color_fill_hover: ?dvui.ColorOrGradient = null,
    color_fill_press: ?dvui.ColorOrGradient = null,
    color_text: ?dvui.ColorOrGradient = null,
    color_text_hover: ?dvui.ColorOrGradient = null,
    color_text_press: ?dvui.ColorOrGradient = null,
    color_border: ?dvui.ColorOrGradient = null,
    ninepatch_fill: ?*const Ninepatch = null,
    ninepatch_hover: ?*const Ninepatch = null,
    ninepatch_press: ?*const Ninepatch = null,
    style: Theme.Style.Name = .content,
    theme: ?*const Theme = null,
    font: ?Font = null,
    rotation: f32 = 0,
    margin: Rect = Rect{},
    border: Rect = Rect{},
    padding: Rect = Rect{},
    corners: CornerRect = CornerRect{},
    min_size_content: Size = Size{},
    max_size_content: ContextLayer.MaxSize = .{ .w = dvui.max_float_safe, .h = dvui.max_float_safe },
    background: bool = false,
    box_shadow: ?ContextLayer.BoxShadow = null,
};

test "every Context_Prototype field has a default" {
    // Constructing the prototype empty is the check: Zig rejects a field with
    // no default, and names it.
    const empty: Context_Prototype = .{};
    _ = empty;
}

test "ContextLayer carries every Context_Prototype field as a nullable" {
    inline for (@typeInfo(Context_Prototype).@"struct".field_names) |f_name| {
        if (!@hasField(ContextLayer, f_name)) {
            @compileError("ContextLayer is missing " ++ f_name);
        }
        if (@typeInfo(@FieldType(ContextLayer, f_name)) != .optional) {
            @compileError("ContextLayer." ++ f_name ++ " is not optional");
        }
    }
}

test "stored values fit and align in their cells" {
    comptime {
        for (@typeInfo(ContextLayer).@"struct".field_names) |f_name| {
            if (std.mem.eql(u8, f_name, "_base")) continue;
            const T = ContextLayer.Payload(f_name);
            // A cell holds one value, addressed as a *T, so its size must cover
            // the value and its stride must satisfy the type's alignment.
            if (@sizeOf(T) > ContextLayer.cell_size) @compileError("cell too small for " ++ f_name);
            if (@alignOf(T) > ContextLayer.cell_align) @compileError("cell alignment too small for " ++ f_name);
            if (ContextLayer.cell_size % @alignOf(T) != 0) @compileError("cell stride breaks alignment of " ++ f_name);
        }
    }
}

test "Tag names every field of a layer, in order" {
    comptime {
        var expected: usize = 0;
        for (@typeInfo(ContextLayer).@"struct".field_names) |f_name| {
            if (std.mem.eql(u8, f_name, "_base")) continue;
            if (!@hasField(ContextLayer.Tag, f_name)) @compileError("Tag is missing " ++ f_name);
            if (@intFromEnum(@field(ContextLayer.Tag, f_name)) != expected) @compileError("Tag order is wrong at " ++ f_name);
            expected += 1;
        }
        if (expected > @bitSizeOf(ContextLayer.Mask)) @compileError("Mask is too narrow for the layer's fields");
    }
}

test "a stored layer reads back what it wrote" {
    const layer: ContextLayer = .{
        .name = "x",
        .style = .highlight,
        .padding = .all(2),
        .expand = .vertical,
        .tab_index = 9,
        .background = true,
    };

    const cells = layer.valueCount();
    var buf: [8 * ContextLayer.cell_size]u8 align(ContextLayer.cell_align) = undefined;
    const values = buf[0 .. cells * ContextLayer.cell_size];
    const mask = layer.writeLayer(values);
    const slot: ContextLayer.Slot = .{ .mask = mask, .values = values };

    if (!std.mem.eql(u8, slot.read("name", slot.cellOf("name").?), "x")) return error.BadName;
    if (slot.read("style", slot.cellOf("style").?) != .highlight) return error.BadStyle;
    if (slot.read("padding", slot.cellOf("padding").?).x != 2) return error.BadPadding;
    if (slot.read("expand", slot.cellOf("expand").?) != .vertical) return error.BadExpand;
    if (slot.read("tab_index", slot.cellOf("tab_index").?) != 9) return error.BadTab;
    if (!slot.read("background", slot.cellOf("background").?)) return error.BadBackground;
    if (slot.cellOf("margin") != null) return error.PhantomField;
}
