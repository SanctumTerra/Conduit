const std = @import("std");
const Protocol = @import("protocol");
const BlockPermutation = @import("./block-permutation.zig").BlockPermutation;
const BlockType = @import("./block-type.zig").BlockType;
const Dimension = @import("../dimension/dimension.zig").Dimension;
const Chunk = @import("../chunk/chunk.zig").Chunk;
const trait_mod = @import("./traits/trait.zig");
const BlockTraitInstance = trait_mod.BlockTraitInstance;
const Event = trait_mod.Event;
const Player = @import("../../player/player.zig").Player;

pub const Block = struct {
    position: Protocol.BlockPosition,
    dimension: *Dimension,
    allocator: std.mem.Allocator,
    traits: std.ArrayListUnmanaged(BlockTraitInstance),

    pub fn init(allocator: std.mem.Allocator, dimension: *Dimension, position: Protocol.BlockPosition) Block {
        return .{
            .position = position,
            .dimension = dimension,
            .allocator = allocator,
            .traits = .{},
        };
    }

    pub fn deinit(self: *Block) void {
        for (self.traits.items) |instance| {
            if (instance.vtable.onDetach) |f| f(instance.ctx, self);
            if (instance.vtable.destroyFn) |f| f(instance.ctx, self.allocator);
        }
        self.traits.deinit(self.allocator);
    }

    pub fn addTrait(self: *Block, instance: BlockTraitInstance) !void {
        try self.traits.append(self.allocator, instance);
        if (instance.vtable.onAttach) |f| f(instance.ctx, self);
    }

    pub fn removeTrait(self: *Block, id: []const u8) void {
        for (self.traits.items, 0..) |instance, i| {
            if (std.mem.eql(u8, instance.identifier, id)) {
                if (instance.vtable.onDetach) |f| f(instance.ctx, self);
                if (instance.vtable.destroyFn) |f| f(instance.ctx, self.allocator);
                _ = self.traits.swapRemove(i);
                return;
            }
        }
    }

    pub fn hasTrait(self: *const Block, id: []const u8) bool {
        for (self.traits.items) |instance| {
            if (std.mem.eql(u8, instance.identifier, id)) return true;
        }
        return false;
    }

    pub fn getTrait(self: *const Block, id: []const u8) ?BlockTraitInstance {
        for (self.traits.items) |instance| {
            if (std.mem.eql(u8, instance.identifier, id)) return instance;
        }
        return null;
    }

    pub fn getTraitState(self: *const Block, comptime T: type) ?*T.TraitState {
        for (self.traits.items) |instance| {
            if (std.mem.eql(u8, instance.identifier, T.identifier)) {
                return @ptrCast(@alignCast(instance.ctx));
            }
        }
        return null;
    }

    pub fn fireEvent(self: *Block, comptime event: Event, args: anytype) Event.ReturnType(event) {
        for (self.traits.items) |instance| {
            if (instance.vtable.get(event)) |f| {
                const result = @call(.auto, f, .{instance.ctx} ++ args);
                if (Event.ReturnType(event) == bool) {
                    if (!result) return false;
                }
            }
        }
        if (Event.ReturnType(event) == bool) return true;
    }

    pub fn getPermutation(self: *const Block, layer: usize) !*BlockPermutation {
        return self.dimension.getPermutation(self.position, layer);
    }

    pub fn setPermutation(self: *const Block, permutation: *BlockPermutation, layer: usize) !void {
        return self.dimension.setPermutation(self.position, permutation, layer);
    }

    pub fn getType(self: *const Block) ?*BlockType {
        const perm = self.getPermutation(0) catch return null;
        return BlockType.get(perm.identifier);
    }

    pub fn getIdentifier(self: *const Block) []const u8 {
        const perm = self.getPermutation(0) catch return "minecraft:air";
        return perm.identifier;
    }

    pub fn isAir(self: *const Block) bool {
        return std.mem.eql(u8, self.getIdentifier(), "minecraft:air");
    }

    pub fn getChunk(self: *const Block) ?*Chunk {
        const cx = self.position.x >> 4;
        const cz = self.position.z >> 4;
        return self.dimension.getChunk(cx, cz);
    }

    pub fn above(self: *const Block, steps: i32) Block {
        return init(self.allocator, self.dimension, .{
            .x = self.position.x,
            .y = self.position.y + steps,
            .z = self.position.z,
        });
    }

    pub fn below(self: *const Block, steps: i32) Block {
        return init(self.allocator, self.dimension, .{
            .x = self.position.x,
            .y = self.position.y - steps,
            .z = self.position.z,
        });
    }

    pub fn north(self: *const Block, steps: i32) Block {
        return init(self.allocator, self.dimension, .{
            .x = self.position.x,
            .y = self.position.y,
            .z = self.position.z - steps,
        });
    }

    pub fn south(self: *const Block, steps: i32) Block {
        return init(self.allocator, self.dimension, .{
            .x = self.position.x,
            .y = self.position.y,
            .z = self.position.z + steps,
        });
    }

    pub fn east(self: *const Block, steps: i32) Block {
        return init(self.allocator, self.dimension, .{
            .x = self.position.x + steps,
            .y = self.position.y,
            .z = self.position.z,
        });
    }

    pub fn west(self: *const Block, steps: i32) Block {
        return init(self.allocator, self.dimension, .{
            .x = self.position.x - steps,
            .y = self.position.y,
            .z = self.position.z,
        });
    }
};
