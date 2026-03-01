const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;
const BlockPosition = @import("../types/block-position.zig").BlockPosition;
const NBT = @import("nbt");
const CompoundTag = NBT.CompoundTag;

pub const BlockActorDataPacket = struct {
    position: BlockPosition,
    nbt: CompoundTag,

    pub fn serialize(self: *const BlockActorDataPacket, stream: *BinaryStream, allocator: @import("std").mem.Allocator) ![]const u8 {
        try stream.writeVarInt(Packet.BlockActorData);
        try BlockPosition.write(stream, self.position);

        var nbt_stream = BinaryStream.init(allocator, null, null);
        defer nbt_stream.deinit();
        var nbt_copy = self.nbt;
        try CompoundTag.write(&nbt_stream, &nbt_copy, NBT.ReadWriteOptions.network);
        const nbt_buf = nbt_stream.getBuffer();
        try stream.write(nbt_buf);

        return stream.getBuffer();
    }
};
