const Raknet = @import("Raknet");
const NetworkHandler = @import("../network-handler.zig").NetworkHandler;
const BinaryStream = @import("BinaryStream").BinaryStream;
const Protocol = @import("protocol");

pub fn handlePacketViolationWarning(
    _: *NetworkHandler,
    _: *Raknet.Connection,
    stream: *BinaryStream,
) !void {
    const packet = Protocol.PacketViolationWarningPacket.deserialize(stream) catch return;
    Raknet.Logger.ERROR("PacketViolationWarning: type={d} severity={d} packetId=0x{x} context={s}", .{
        packet.violation_type,
        packet.severity,
        packet.packet_id,
        packet.context,
    });
}
