pub const Packets = struct {
    pub const RequestNetworkSettings = 0xc1;
    pub const NetworkSettings = 0x8f;
    pub const Login = 0x01;
    pub const PlayStatus = 0x02;
    pub const ResourcePackInfo = 0x06;
    pub const ResourcePackStack = 0x07;
    pub const ResourcePackResponse = 0x08;
    pub const Text = 0x09;
    pub const StartGame = 0x0b;
    pub const ClientCacheStatus = 0x81;
    pub const ItemRegistry = 0xa2;
};
