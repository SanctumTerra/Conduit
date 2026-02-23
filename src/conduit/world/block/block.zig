const std = @import("std");
const Protocol = @import("protocol");
const BlockPermutation = @import("./block-permutation.zig").BlockPermutation;
const BlockType = @import("./block-type.zig").BlockType;
const Dimension = @import("../dimension/dimension.zig").Dimension;
const Chunk = @import("../chunk/chunk.zig").Chunk;

pub const Block = struct {
    position: Protocol.BlockPosition,
    dimension: *Dimension,

    pub fn init(dimension: *Dimension, position: Protocol.BlockPosition) Block {
        return .{
            .position = position,
            .dimension = dimension,
        };
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
        return init(self.dimension, .{
            .x = self.position.x,
            .y = self.position.y + steps,
            .z = self.position.z,
        });
    }

    pub fn below(self: *const Block, steps: i32) Block {
        return init(self.dimension, .{
            .x = self.position.x,
            .y = self.position.y - steps,
            .z = self.position.z,
        });
    }

    pub fn north(self: *const Block, steps: i32) Block {
        return init(self.dimension, .{
            .x = self.position.x,
            .y = self.position.y,
            .z = self.position.z - steps,
        });
    }

    pub fn south(self: *const Block, steps: i32) Block {
        return init(self.dimension, .{
            .x = self.position.x,
            .y = self.position.y,
            .z = self.position.z + steps,
        });
    }

    pub fn east(self: *const Block, steps: i32) Block {
        return init(self.dimension, .{
            .x = self.position.x + steps,
            .y = self.position.y,
            .z = self.position.z,
        });
    }

    pub fn west(self: *const Block, steps: i32) Block {
        return init(self.dimension, .{
            .x = self.position.x - steps,
            .y = self.position.y,
            .z = self.position.z,
        });
    }
};
