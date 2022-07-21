version = 3 -- Lua Version. Dont touch this
ScenarioInfo = {
    name = "DarkSurvival",
    description = "START WAVE: 1800, WAVE: 360",
    preview = '',
    map_version = 20,
    type = 'skirmish',
    starts = true,
    size = {1024, 1024},
    reclaim = {109846, 399247.1},
    map = '/maps/Survival_NorthSouth_Barrens.v0020/Survival_NorthSouth_Barrens.scmap',
    save = '/maps/Survival_NorthSouth_Barrens.v0020/Survival_NorthSouth_Barrens_save.lua',
    script = '/maps/Survival_NorthSouth_Barrens.v0020/Survival_NorthSouth_Barrens_script.lua',
    norushradius = 0,
    Configurations = {
        ['standard'] = {
            teams = {
                {
                    name = 'FFA',
                    armies = {'ARMY_1', 'ARMY_2', 'ARMY_3', 'ARMY_4'}
                },
            },
            customprops = {
                ['ExtraArmies'] = STRING( 'ARMY_SUPERWEAPON ARMY_SURVIVAL_ENEMY' ),
            },
        },
    },
}
