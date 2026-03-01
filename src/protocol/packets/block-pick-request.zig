const BinaryStream = @import("BinaryStream").BinaryStream;
const BlockPosition = @import("../types/block-position.zig").BlockPosition;

pub const BlockPickRequestPacket = struct {
    position: BlockPosition,
    add_user_data: bool,
    selected_slot: u8,

    pub fn deserialize(stream: *BinaryStream) !BlockPickRequestPacket {
        _ = try stream.readVarInt();
        const x = try stream.readZigZag();
        const y = try stream.readZigZag();
        const z = try stream.readZigZag();
        const add_user_data = try stream.readBool();
        const selected_slot = try stream.readUint8();
        return .{
            .position = BlockPosition.init(x, y, z),
            .add_user_data = add_user_data,
            .selected_slot = selected_slot,
        };
    }
};
