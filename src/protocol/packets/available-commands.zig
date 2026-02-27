const BinaryStream = @import("BinaryStream").BinaryStream;
const Packet = @import("../root.zig").Packet;

pub const PacketCommandEnum = struct {
    name: []const u8,
    value_indices: []const u32,
};

pub const PacketCommand = struct {
    name: []const u8,
    description: []const u8,
    flags: u16,
    permission_level: u8,
    aliases_offset: u32,
    chained_offsets: []const u32,
    overloads: []const PacketOverload,
};

pub const PacketOverload = struct {
    chaining: bool = false,
    params: []const PacketParameter,
};

pub const PacketParameter = struct {
    name: []const u8,
    type_field: u32,
    optional: bool,
    options: u8,
};

pub const PacketDynamicEnum = struct {
    name: []const u8,
    values: []const []const u8,
};

pub const CommandEnumConstraint = struct {
    enum_index: u32,
    value_index: u32,
    constraints: []const u8,
};

pub const ChainedSubcommandValue = struct {
    name: []const u8,
};

pub const ChainedSubcommand = struct {
    name: []const u8,
    values: []const ChainedSubcommandIndex,
};

pub const ChainedSubcommandIndex = struct {
    index: u32,
};

pub const AvailableCommandsPacket = struct {
    enum_values: []const []const u8 = &.{},
    chained_subcommand_values: []const []const u8 = &.{},
    suffixes: []const []const u8 = &.{},
    enums: []const PacketCommandEnum = &.{},
    chained_subcommands: []const ChainedSubcommand = &.{},
    commands: []const PacketCommand = &.{},
    dynamic_enums: []const PacketDynamicEnum = &.{},
    constraints: []const CommandEnumConstraint = &.{},

    pub fn serialize(self: *const AvailableCommandsPacket, stream: *BinaryStream) ![]const u8 {
        try stream.writeVarInt(Packet.AvailableCommands);

        try stream.writeVarInt(@intCast(self.enum_values.len));
        for (self.enum_values) |val| {
            try stream.writeVarString(val);
        }

        try stream.writeVarInt(@intCast(self.chained_subcommand_values.len));
        for (self.chained_subcommand_values) |val| {
            try stream.writeVarString(val);
        }

        try stream.writeVarInt(@intCast(self.suffixes.len));
        for (self.suffixes) |val| {
            try stream.writeVarString(val);
        }

        try stream.writeVarInt(@intCast(self.enums.len));
        for (self.enums) |e| {
            try stream.writeVarString(e.name);
            try stream.writeVarInt(@intCast(e.value_indices.len));
            for (e.value_indices) |idx| {
                try stream.writeUint32(idx, .Little);
            }
        }

        try stream.writeVarInt(@intCast(self.chained_subcommands.len));
        for (self.chained_subcommands) |cs| {
            try stream.writeVarString(cs.name);
            try stream.writeVarInt(@intCast(cs.values.len));
            for (cs.values) |v| {
                try stream.writeUint32(v.index, .Little);
            }
        }

        try stream.writeVarInt(@intCast(self.commands.len));
        for (self.commands) |cmd| {
            try stream.writeVarString(cmd.name);
            try stream.writeVarString(cmd.description);
            try stream.writeUint16(cmd.flags, .Little);
            try stream.writeUint8(cmd.permission_level);
            try stream.writeUint32(cmd.aliases_offset, .Little);
            try stream.writeVarInt(@intCast(cmd.chained_offsets.len));
            for (cmd.chained_offsets) |offset| {
                try stream.writeUint32(offset, .Little);
            }
            try stream.writeVarInt(@intCast(cmd.overloads.len));
            for (cmd.overloads) |overload| {
                try stream.writeBool(overload.chaining);
                try stream.writeVarInt(@intCast(overload.params.len));
                for (overload.params) |param| {
                    try stream.writeVarString(param.name);
                    try stream.writeUint32(param.type_field, .Little);
                    try stream.writeBool(param.optional);
                    try stream.writeUint8(param.options);
                }
            }
        }

        try stream.writeVarInt(@intCast(self.dynamic_enums.len));
        for (self.dynamic_enums) |de| {
            try stream.writeVarString(de.name);
            try stream.writeVarInt(@intCast(de.values.len));
            for (de.values) |val| {
                try stream.writeVarString(val);
            }
        }

        try stream.writeVarInt(@intCast(self.constraints.len));
        for (self.constraints) |c| {
            try stream.writeUint32(c.enum_index, .Little);
            try stream.writeUint32(c.value_index, .Little);
            try stream.writeVarInt(@intCast(c.constraints.len));
            for (c.constraints) |constraint_val| {
                try stream.writeUint8(constraint_val);
            }
        }

        return stream.getBuffer();
    }
};
