pub const MoveDeltaFlags = struct {
    pub const None: u16 = 0;
    pub const HasX: u16 = 1 << 0;
    pub const HasY: u16 = 1 << 1;
    pub const HasZ: u16 = 1 << 2;
    pub const HasRotX: u16 = 1 << 3;
    pub const HasRotY: u16 = 1 << 4;
    pub const HasRotZ: u16 = 1 << 5;
    pub const OnGround: u16 = 1 << 6;
    pub const Teleport: u16 = 1 << 7;
    pub const ForceMove: u16 = 1 << 8;
    pub const All: u16 = HasX | HasY | HasZ | HasRotX | HasRotY | HasRotZ;

    pub fn hasFlag(flags: u16, flag: u16) bool {
        return (flags & flag) != 0;
    }
};
