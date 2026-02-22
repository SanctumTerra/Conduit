pub const AttributeName = enum {
    Absorption,
    AttackDamage,
    FallDamage,
    FollowRange,
    Health,
    HorseJumpStrength,
    KnockbackResistence,
    LavaMovement,
    Luck,
    Movement,
    PlayerExhaustion,
    PlayerExperience,
    PlayerHunger,
    PlayerLevel,
    PlayerSaturation,
    UnderwaterMovement,
    ZombieSpawnReinforcements,

    pub fn toString(self: AttributeName) []const u8 {
        return switch (self) {
            .Absorption => "minecraft:absorption",
            .AttackDamage => "minecraft:attack_damage",
            .FallDamage => "minecraft:fall_damage",
            .FollowRange => "minecraft:follow_range",
            .Health => "minecraft:health",
            .HorseJumpStrength => "minecraft:horse.jump_strength",
            .KnockbackResistence => "minecraft:knockback_resistance",
            .LavaMovement => "minecraft:lava_movement",
            .Luck => "minecraft:luck",
            .Movement => "minecraft:movement",
            .PlayerExhaustion => "minecraft:player.exhaustion",
            .PlayerExperience => "minecraft:player.experience",
            .PlayerHunger => "minecraft:player.hunger",
            .PlayerLevel => "minecraft:player.level",
            .PlayerSaturation => "minecraft:player.saturation",
            .UnderwaterMovement => "minecraft:underwater_movement",
            .ZombieSpawnReinforcements => "minecraft:zombie.spawn_reinforcements",
        };
    }

    pub fn fromString(str: []const u8) ?AttributeName {
        const map = std.ComptimeStringMap(AttributeName, .{
            .{ "minecraft:absorption", .Absorption },
            .{ "minecraft:attack_damage", .AttackDamage },
            .{ "minecraft:fall_damage", .FallDamage },
            .{ "minecraft:follow_range", .FollowRange },
            .{ "minecraft:health", .Health },
            .{ "minecraft:horse.jump_strength", .HorseJumpStrength },
            .{ "minecraft:knockback_resistance", .KnockbackResistence },
            .{ "minecraft:lava_movement", .LavaMovement },
            .{ "minecraft:luck", .Luck },
            .{ "minecraft:movement", .Movement },
            .{ "minecraft:player.exhaustion", .PlayerExhaustion },
            .{ "minecraft:player.experience", .PlayerExperience },
            .{ "minecraft:player.hunger", .PlayerHunger },
            .{ "minecraft:player.level", .PlayerLevel },
            .{ "minecraft:player.saturation", .PlayerSaturation },
            .{ "minecraft:underwater_movement", .UnderwaterMovement },
            .{ "minecraft:zombie.spawn_reinforcements", .ZombieSpawnReinforcements },
        });
        return map.get(str);
    }
};

const std = @import("std");
