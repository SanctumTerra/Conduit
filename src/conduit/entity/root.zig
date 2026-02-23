pub const Entity = @import("./entity.zig").Entity;
pub const EntityType = @import("./entity-type.zig").EntityType;
pub const EntityTypeRegistry = @import("./entity-type-registry.zig");

pub const metadata = @import("./metadata/root.zig");
pub const EntityActorFlags = metadata.EntityActorFlags;
pub const Attributes = metadata.Attributes;

pub const traits = @import("./traits/root.zig");
pub const EntityTrait = traits.EntityTrait;
pub const EntityTraitInstance = traits.EntityTraitInstance;
pub const EntityTraitVTable = traits.EntityTraitVTable;
pub const Event = traits.Event;
