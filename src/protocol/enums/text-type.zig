pub const TextType = enum(u8) {
    Raw = 0,
    Chat = 1,
    Translation = 2,
    Popup = 3,
    JukeboxPopup = 4,
    Tip = 5,
    System = 6,
    Whisper = 7,
    Announcement = 8,
    ObjectWhisper = 9,
    Object = 10,
    ObjectAnnouncement = 11,
};
