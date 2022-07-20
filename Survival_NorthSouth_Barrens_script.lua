-- ######################################## --
-- ##           Survival *EXtremeDesertV3fA*				## --
-- ##           Game Logic Script							## -- 
-- ##           (c) tecxx@rrs.at							## --
-- ##           29.11.07								## --
-- ##                                                                                                           ## --
-- ##           08 June 08 Cobaltur adoopted for map 	     		## --
-- ##           Survival NorhtNSouth Barrens					## --
-- ##           Waypoints extended						## --
-- ######################################## --

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- imports and variables
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local ScenarioUtils = import('/lua/sim/ScenarioUtilities.lua');
local ScenarioFramework = import('/lua/ScenarioFramework.lua');
local Utilities = import('/lua/utilities.lua');
local Entity = import('/lua/sim/Entity.lua').Entity;

-- global vars
local gameEnd = false;		-- true when game is over
local beatTime = 1;			-- seconds to wait between game logic calculations
local playercount = 0;		-- how many human players?

-- survival mode
local loopEnd = false;		-- true if all waves were spawned
local waveid = 0;			-- which wave gets spawned, starts at 0
local loop = 0;				-- which loop are we playing, starts at 0
local numGatesOpen = 0; 	-- how many spawn gates are alive
local gates = {nil, nil, nil, nil, nil, nil, nil, nil};	-- gate pointers
local numSpecialsOpen = 0;	-- how many special weapons are alive
local specials = {nil, nil, nil, nil}; -- special pointers
local killCount = { ARMY_1 = 0,		-- number of gates/specials killed by each player+2 ai's
					ARMY_2 = 0,
					ARMY_3 = 0,
					ARMY_4 = 0,
					ARMY_SUPERWEAPON = 0,
					ARMY_SURVIVAL_ENEMY = 0};



------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- engine invoked main functions
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- this function is called once before game start, it does some player initialization
function OnPopulate()

	-- make default settings work
	if (ScenarioInfo.Options.opt_difficulty == nil) then
		ScenarioInfo.Options.opt_difficulty = 1.00;
	end
	if (ScenarioInfo.Options.opt_startupTime == nil) then
		ScenarioInfo.Options.opt_startupTime = 90;
	end
	if (ScenarioInfo.Options.opt_waveTime == nil) then
		ScenarioInfo.Options.opt_waveTime = 60;
	end
	if (ScenarioInfo.Options.opt_defenseObject == nil) then
		ScenarioInfo.Options.opt_defenseObject = 1;
	end

	ScenarioUtils.InitializeArmies();
	ScenarioFramework.SetPlayableArea('AREA_1', false);

	-- count number of players
	local armies = ListArmies();
	playercount = table.getn(armies) - 2;	-- num armies minus 2 ai players
	LOG("___SE___ PlayerCount: "..playercount);
end

-- this function creates all mex and hydrocarbon markers
-- resource scale script (c) Jotto, reworked by tecxx
function ScenarioUtils.CreateResources()
	-- fetch markers and iterate them
	local markers = ScenarioUtils.GetMarkers();
	for i, tblData in pairs(markers) do
		-- spawn resources?
		local doit = false;
		if (tblData.resource and not tblData.SpawnWithArmy) then
			-- standard resources, spawn it
			doit = true;
		elseif (tblData.resource and tblData.SpawnWithArmy) then
			-- resources bound to player, check if army is presend
			for j, army in ListArmies() do
				if (tblData.SpawnWithArmy == army) then
					doit = true;  -- we made sure the army is present, allow spawn
					break;
				end
			end
		end

		if (doit) then
			-- check type of resource and set parameters
			local bp, albedo, sx, sz, lod;
			if (tblData.type == "Mass") then
				albedo = "/env/common/splats/mass_marker.dds";
				bp = "/env/common/props/massDeposit01_prop.bp";
				sx = 2;
				sz = 2;
				lod = 100;
			else
				albedo = "/env/common/splats/hydrocarbon_marker.dds";
				bp = "/env/common/props/hydrocarbonDeposit01_prop.bp";
				sx = 6;
				sz = 6;
				lod = 200;
			end
			-- create the resource
			CreateResourceDeposit(tblData.type,	tblData.position[1], tblData.position[2], tblData.position[3], tblData.size);
			-- create the resource graphic on the map
			CreatePropHPR(bp, tblData.position[1], tblData.position[2], tblData.position[3], Random(0,360), 0, 0);
			-- create the resource icon on the map
			CreateSplat(
					tblData.position,           # Position
			0,                          # Heading (rotation)
		albedo,                     # Texture name for albedo
		sx, sz,                     # SizeX/Z
			lod,                        # LOD
			0,                          # Duration (0 == does not expire)
		-1,                         # army (-1 == not owned by any single army)
			0							# ???
			);
		end
	end
end

-- start of map script
function OnStart(self)
	-- initiate game modes and spawn players
	setupGame();

	-- start the game logic
	startScenarioThreads();

	-- set score calculation to show total kills
	for index, brain in ArmyBrains do
		brain.CalculateScore = function(thisBrain)
			return armyKills(thisBrain) + killCount[ArmyIndexer(thisBrain)]*1000;
		end
	end
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- main game logic
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--creates the different scenario threads 
startScenarioThreads = function()
	--start main thread
	local mainThread = ForkThread(function(self)
		LOG("___SE___ Main thread running!");

		while (gameEnd == false) do
			--wait time between each beat
			WaitSeconds(beatTime);
			-- run game logic
			gameLogic();
		end

		KillThread(self);
	end);

	--this creates a new spawn thread,, only in survival mode
	local spawnThread = ForkThread(spawnThread);
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- survival mode
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- unit tables, seperated by air/ground
local unitTableAir = {
	{ -- tech1
	

		'xra0105', 	-- cybran t1 light gunship
		
	},
	{ -- tech2
		'UAA0203',	-- aeon gunship
		'URA0203',	-- cybran gunship
		'UEA0203',	-- uef gunship
	
		'xsa0203',	-- seraphim gunship
	},
	{ -- tech3
	
		'UEA0305',	-- uef t3 gunship

		'xaa0305', 	-- aeon T3 AA gunship
		'xra0305', 	-- cybran T3 gunship
	
	},
	{ -- tech4
		'xea0306',	-- UEF t3 heavy air transport
	},
	{ -- tech 5
		'UAA0310', -- czar
		'URA0401', -- soul ripper
		'xsa0402', -- seraphim exp bomber
	},
};

local unitTableGround = {
	{ -- tech 1
		--BROT1EXM1', -- QUADRO BOT
		--BROT2EXM2', -- GONARCH
		--BRPT1EXPBOT1', -- TAANTUM
		--BRPT1EXTANK2', -- YASUS
		--BRNT1ADVBOT', -- WARDEN
		--BRNT1EXM1', -- KRUGER
		--BRNT1EXTK', -- THUNDERSTRIKE
		--BRMT1BEETLE', -- KARAKUT
		--BRMT1EXM1', -- LASERBOT
		--BRMT1EXTANK', -- TALON
		
		
	},
	{ -- tech 2
		'UAL0202', -- aeon t2 tank
		
		'UAL0307', -- aeon t2 shield
		'UAL0205', -- aeon t2 aa
		'URL0202', -- cybran t2 tank
		'URL0203', -- cybran t2 amphibious tank
	
		
		'URL0205', -- cybran t2 aa
		'UEL0202', -- uef t2 tank
		'UEL0203', -- uef t2 amphibious tank
	
		'UEL0307', -- uef t2 shield
		'UEL0205', -- uef t2 aa	
		'DRL0204', -- cybran t2 rocket
		'DEL0204', -- uef t2 gatling
		'xal0203', -- aeon t2 assault tank
	
		'xsl0202', -- seraphim t2 assault bot
		'xsl0203', -- seraphim t2 hover tank
		'xsl0205', -- seraphim t2 anti air
		
		'BRMT1ADVBOT', -- REDHAWK
		'BRMT2MEDM', -- PYRITE
		'BRMT2WILDCAT', -- WILDCAT
		--BRNT1WXMOB', -- UNDERTAKER
		'BRNT2BM', -- BANSHEE
		'BRNT2EXLM', -- FIRESTORM
		'BROT1EXM1', -- JACKHAMMER
		'BRNT2EXMDF', -- HORIZON
		'BRNT2SNIPER1', -- MARKSMAN
		--BROTEXTANK1', -- TRIDYMITE
		--BROT2ASB', -- TERMINATOR
		--BROT3EXBM', -- AKUMA
		--BRPT1BTBOT', -- THA-YATH
		--BRPTEXPOT', -- YENAH-LAO
		--UAL0402', -- RAMPAGE
	},
	{ -- tech 3
		'UAL0304', -- aeon t3 arty
		'UAL0303', -- aeon t3 assault bot
		'URL0304', -- cybran t3 arty
		'URL0303', -- cybran t3 assault bot
		'UEL0304', -- uef t3 arty
		'UEL0303', -- uef t3 assault bot
		'DAL0310', -- aeon shield disruptor

		'xal0305',	-- aeon sniper bot
		'xrl0305', 	-- cybran t3 armored assault bot
		'xel0305', 	-- uef t3 armored assault bot
		'xel0306',	-- uef t3 mobile missile platform

		'xsl0304',	-- seraphim t3 heavy artillery
		'xsl0307', -- seraphim t3 mobile shield gen
		'xsl0303',	-- seraphim t3 siege tank
		'xsl0305',	-- seraphim t3 sniper bot
		
		
		'UAL0301', -- aeon support commander
		'URL0301', -- cybran support commander 
		'UEL0301', -- uef support commander
		'xsl0301', -- seraphim support commander
		--BAL0401', -- INQUISITOR
		--BRMT3ADVTBOR', -- CONSOLIDATOR
		--BRMT3GARG', -- GARGANTUA
		--BRNT3ADVTBOT1', -- HURRICANE
		'BRNT3OW', -- OWENS
		'BROT3COUG1', -- COUGAR
		'BRPT2HVBOT1313', -- ATHUSIL
		'UAL04021', -- OVERLORD
		'UEL0401', -- ТОЛСТЯК
		'WSL0404', -- ECHIBUM
		'WAL44041', -- MARAUDER
		'BRMT3MCM', -- MADCAT
		'URL0402', -- MONKEYLORD
		'WRL04041', -- MONOLITH
		'BRNT3ARGUS', -- ARGUS
		'UAL04011', -- COLOSS
		'XSL0401', -- ITOTHA
	},
	{ -- tech 4
		'URS0201', -- cybran salem class
		'URS0201', -- cybran salem class		-- double entry to increase spawn chance
		'UAL0301', -- aeon support commander
		'URL0301', -- cybran support commander 
		'UEL0301', -- uef support commander
		'xsl0301', -- seraphim support commander
		
		
	},
	{ -- tech 5
		'UAL0401', -- aeon galactic colossus
		--'URL0401', -- cybran scathis disabled for now - it's too strong
		'URL0402', -- cybran monkeylord
		'UEL0401', -- uef fatboy

		'xrl0403',	-- cybran experimental megabot
		'xsl0401',	-- seraphim experimental assault bot
		
		'BRL0401', -- BASILISK
		'BRMT3AVA', -- AVALANCHE
		'BRMT3MCM4', -- MADCAT MK4
		'BRMT3SNAKE', -- DEVIL
		'URL40321', -- KIBROS OLD GOD
		'WRL24661', -- CYBER GOD BRACKMAN
		'BEL0402', -- GOLIATH
		'BRNT3DOOMSDAY1', -- DOOMSDAY
		'BRNT3SHBM2', -- MAYHEM MK4
		'BROT3HADES123', -- HADES
		'BROT3NCM211', -- NOVA CAT MK2
		'BRPTSNBM', -- MEGA TITAN
		'WEL0416', -- IMMORTAL
		'XS104041', -- KWAHT HOVATHAM T4 MOBILE ARTY
		'BRNT3BAT', -- RAMPART
		'XSL0405', -- ITHOTA MK2
	},
};

-- special units, get spawned at end of loop
local unitTableSpecials = {
	{
		-- artilleries
		'uab2302', -- Aeon emissary
		'xab2307', -- Aeon salvation
		'urb2302', -- cybran disruptor
		'ueb2302', -- UEF duke
		'ueb2401', -- UEF mavor
		'xsb2302', -- seraphim hovatham

		-- nukes
		'xsb2305', -- seraphim hastue
		'xsb2401', -- seraphim yolana oss
		'ueb2305', -- UEF Stonager
		'urb2305', -- Cybran Liberator
		'uab2305', -- Aeon apocalypse
	},
};

-- upgrades list for SCU's
local upgradeTable = {
	-- aeon
	A={
		'Shield',
		'ShieldHeavy',
		'StabilitySuppressant',
		'SystemIntegrityCompensator',
	},
	-- cybran
	R={
		'CloakingGenerator',
		'EMPCharge',
		'FocusConvertor',
		'NaniteMissileSystem',
		'SelfRepairSystem',
		'StealthGenerator', -- NOTE requires cloaking generator first
	},
	-- uef
	E={
		'AdvancedCoolingUpgrade',
		'HighExplosiveOrdnance',
		'RadarJammer',
		'Shield',
		'ShieldGeneratorField',
	},
	-- seraphim
	S={
		'DamageStabilization',
		'Missile',
		'Overcharge',
		'Shield',
	},
};

-- defines possible formations for the units
local formationTable = {
	'AttackFormation',
	
};

-- this table defines the wave combos: spawn how many techlevel = {ground, air}  units
local waveTable = {
	--	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 1,  0}, t5 = { 0,  0}},
	-- round 1
	{t1 = {10,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {12,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {15,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {20,  0}, t2 = { 2,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 6
	{t1 = { 0, 10}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {15,  0}, t2 = { 2,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {15,  0}, t2 = { 4,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {15,  0}, t2 = { 6,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 11
	{t1 = { 5, 10}, t2 = { 4,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {20, 10}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = { 5,  0}, t2 = { 5,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {20,  5}, t2 = { 7,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 16
	{t1 = {20,  0}, t2 = {10,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {20,  0}, t2 = {15,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = { 0, 12}, t2 = { 0,  5} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {20,  0}, t2 = { 7,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 21
	{t1 = {20,  5}, t2 = {15,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {20,  0}, t2 = {25,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {20,  0}, t2 = {25,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = { 0, 10}, t2 = { 0,  5} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 26
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = {10,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = { 0,  0}, t2 = {20,  0} , t3 = { 5,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = { 0,  0}, t2 = {10,  0} , t3 = {10,  0}, t4 = { 0,  1}, t5 = { 0,  0}},
	{t1 = { 0,  0}, t2 = {20,  0} , t3 = {10,  0}, t4 = { 0,  1}, t5 = { 0,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 31
	{t1 = { 0,  0}, t2 = { 0,  2} , t3 = { 0,  5}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {30,  0}, t2 = { 0,  0} , t3 = { 5,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {30,  0}, t2 = {10,  0} , t3 = {12,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = {10,  0}, t2 = {20,  0} , t3 = {15,  0}, t4 = { 0,  1}, t5 = { 0,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 36
	{t1 = {30,  0}, t2 = {10,  0} , t3 = {20,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = { 0,  0}, t2 = { 0,  5} , t3 = { 0, 10}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 5,  0}, t5 = { 0,  0}},
	{t1 = { 0,  0}, t2 = {10,  0} , t3 = { 5,  0}, t4 = { 5,  0}, t5 = { 0,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 41
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 2,  1}, t5 = { 1,  0}},
	{t1 = { 0,  0}, t2 = { 5,  0} , t3 = { 0,  0}, t4 = { 8,  0}, t5 = { 0,  0}},
	{t1 = { 0, 10}, t2 = { 0, 10} , t3 = { 0, 12}, t4 = { 0,  1}, t5 = { 0,  0}},
	{t1 = {20,  0}, t2 = { 0,  0} , t3 = { 5,  0}, t4 = { 5,  0}, t5 = { 0,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 46
	{t1 = {10,  0}, t2 = { 5,  0} , t3 = {10,  0}, t4 = { 2,  1}, t5 = { 1,  0}},
	{t1 = {10,  0}, t2 = { 5,  0} , t3 = {20,  0}, t4 = { 0,  0}, t5 = { 0,  0}},
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = {10,  0}, t4 = { 8,  0}, t5 = { 0,  0}},
	{t1 = { 0, 10}, t2 = { 0, 10} , t3 = { 0, 15}, t4 = { 0,  1}, t5 = { 0,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 51
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 2,  0}},
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 0,  1}, t5 = { 0,  2}},
	{t1 = { 0,  0}, t2 = {10,  0} , t3 = { 0,  0}, t4 = { 4,  0}, t5 = { 1,  0}},
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = {8,  0}, t4 = { 4,  0}, t5 = { 1,  0}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},

	-- round 55
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 0,  0}, t5 = { 4,  0}},
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 5,  0}, t5 = { 2,  0}},
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = { 0, 10}, t4 = { 0,  0}, t5 = { 0,  3}},
	{t1={1,0},t2={0,0},t3={0,0},t4={0,0},t5={0,0}},
	{t1 = { 0,  0}, t2 = { 0,  0} , t3 = { 0,  0}, t4 = { 4,  4}, t5 = { 2,  2}},
}

setupGame = function()
	ScenarioInfo.Options.Victory = 'sandbox'; 			-- custom victory condition
	-- misc settings
	Utilities.UserConRequest("ui_ForceLifbarsOnEnemy");	--show enemy life bars
	ScenarioInfo.Options['CivilianAlliance'] = 'enemy';

	-- setup army specific things
	for i, army in ListArmies() do
		if (army == "ARMY_1" or army == "ARMY_2" or army == "ARMY_3" or army == "ARMY_4") then
			-- restrict players from building walls
			ScenarioFramework.AddRestriction(army, categories.WALL);
			-- set alliances
			SetAlliance(army, "ARMY_SURVIVAL_ENEMY", 'Enemy');
			SetAlliance(army, "ARMY_SUPERWEAPON", 'Ally');
			SetAlliedVictory(army, true);
			-- set alliance with all other hill players!
			for j, army2 in ListArmies() do
				if (army2 == "ARMY_1" or army2 == "ARMY_2" or army2 == "ARMY_3" or army2 == "ARMY_4") then
					SetAlliance(army, army2, 'Ally');
				end
			end
		end
	end

	-- spawnwaves and superweapon are enemies
	SetAlliance("ARMY_SURVIVAL_ENEMY", "ARMY_SUPERWEAPON", 'Enemy');
	-- spawnwaves don't have a unit cap
	SetIgnoreArmyUnitCap('ARMY_SURVIVAL_ENEMY', true);

	-- spawn the gates
	spawnGates();
	--spawnScathis();
	--spawnSpecials();
	--fireNukes();

	-- spawn the defense object
	if (ScenarioInfo.Options.opt_defenseObject == -1) then
		return;
	end
	local object = "UEC1902";	-- uef control center
	if (ScenarioInfo.Options.opt_defenseObject == 2) then
		object = "XAB1401";	-- aon exp. resource gen
	end
	if (ScenarioInfo.Options.opt_defenseObject == 3) then
		object = "UEB2401";	-- uef mavor
	end
	if (ScenarioInfo.Options.opt_defenseObject == 4) then
		object = "UAC1101";	-- aeon res. structure
	end

	local pos = ScenarioUtils.MarkerToPosition("HILL_CENTER");
	local def = CreateUnitHPR( object, "ARMY_SUPERWEAPON", pos[1], pos[2], pos[3], 0,0,0);
	def:SetReclaimable(false);
	def:SetCapturable(false);

	-- set onkilled function
	def.OldOnKilled = def.OnKilled;
	def.OnKilled = function(self, instigator, type, overkillRatio)
		--spawn a nuke
		nuke(self:GetPosition());

		msgOut("The defense object has been destroyed. You have lost!");
		self.OldOnKilled(self, instigator, type, overkillRatio);

		loopEnd = true;
		gameEnd = true;
		for i, army in ListArmies() do
			if (army == "ARMY_1" or army == "ARMY_2" or army == "ARMY_3" or army == "ARMY_4") then
				killAllCommanders(army);
				GetArmyBrain(army):OnDefeat();
			end
		end
	end

end

-- spawns 8 scathis at edge of map to prevent players from building outside of hill
spawnScathis = function()
	for i = 1,8 do
		local scName = "SCATHIS"..i;
		local pos = ScenarioUtils.MarkerToPosition(scName);
		local sc = CreateUnitHPR( 'url0401', "ARMY_SURVIVAL_ENEMY", pos[1], pos[2], pos[3], 0,0,0);
		sc:SetReclaimable(false);
		sc:SetCapturable(false);
		sc:SetProductionPerSecondEnergy(99999);
		local wp = sc:GetWeapon(1);
		wp:ChangeMaxRadius(300);

		-- set onkilled function
		sc.OldOnKilled = sc.OnKilled;
		sc.OnKilled = function(self, instigator, type, overkillRatio)
			--spawn a nuke
			nuke(self:GetPosition());

			-- add points to player
			local instArmy = instigator:GetArmy();
			local armyName = ArmyIndexer(GetArmyBrain(instArmy));
			LOG("___SE___ scathis killed, instigator army: "..instArmy.."/"..armyName);
			killCount[armyName] = killCount[armyName] + 1;

			-- handle game logic
			msgOut("A scathis was destroyed by " .. getUsername(instArmy) .. "!");
			self.OldOnKilled(self, instigator, type, overkillRatio);
		end
	end
end

spawnGates = function()
	-- spawn gates at the outer edges for enemy units to teleport in
	-- 8 gates have to be destroyed
	numGatesOpen = 8;
	for i = 1,8 do
		if (gates[i] == nil) then
			local gateName = "Gate"..i;
			local pos = ScenarioUtils.MarkerToPosition(gateName);
			local r = Utilities.GetRandomInt(1,4);
			local gateFaction;
			if (r == 1) then
				gateFaction = 'UAB0304';
			elseif (r == 2) then
				gateFaction = 'URB0304';
			elseif (r == 3) then
				gateFaction = 'UEB0304';
			else
				gateFaction = 'XSB0304';
			end
			gates[i] = CreateUnitHPR( gateFaction, "ARMY_SURVIVAL_ENEMY", pos[1], pos[2], pos[3], 0,0,0);
			gates[i]:SetMaxHealth(500000);
			gates[i]:SetHealth(nil, 500000);
			gates[i]:SetReclaimable(false);
			gates[i]:SetCapturable(false);
			gates[i]:SetProductionPerSecondEnergy(99999);

			-- set gate onkilled function
			gates[i].OldOnKilled = gates[i].OnKilled;
			gates[i].myID = i;
			gates[i].OnKilled = function(self, instigator, type, overkillRatio)
				--spawn a nuke
				nuke(self:GetPosition());

				-- add points to player
				local instArmy = instigator:GetArmy();
				local armyName = ArmyIndexer(GetArmyBrain(instArmy));
				LOG("___SE___ gate killed, id="..self.myID.." instigator army: "..instArmy.."/"..armyName);
				killCount[armyName] = killCount[armyName] + 1;

				-- handle game logic
				numGatesOpen = numGatesOpen - 1;
				msgOut("A gate was destroyed by " .. getUsername(instArmy) .. "! "..numGatesOpen.. " gates left.");
				gates[self.myID] = nil;
				self.OldOnKilled(self, instigator, type, overkillRatio);
				if (numGatesOpen < 1) then
					msgOut("All gates were destroyed!");
				end
			end
		end
	end
end

spawnSpecials = function()
	-- spawn t3 artillery at the 4 outer edges of the map per player
	for i = 1,playercount do
		-- check if it already exists
		if (specials[i] == nil) then
			numSpecialsOpen = numSpecialsOpen + 1;
			local pos = ScenarioUtils.MarkerToPosition("Special"..i);
			local bpCount = table.getn(unitTableSpecials[1]);
			local rr = Utilities.GetRandomInt(1, bpCount);
			local special = unitTableSpecials[1][rr];

			specials[i] = CreateUnitHPR( special, "ARMY_SURVIVAL_ENEMY", pos[1], pos[2], pos[3], 0,0,0);
			specials[i]:SetMaxHealth(300000);
			specials[i]:SetHealth(nil, 300000);
			specials[i]:SetReclaimable(false);
			specials[i]:SetCapturable(false);
			specials[i]:SetProductionPerSecondEnergy(99999);
			specials[i]:SetProductionPerSecondMass(1000);

			-- set special onkilled function
			specials[i].OldOnKilled = specials[i].OnKilled;
			specials[i].myID = i;
			specials[i].OnKilled = function(self, instigator, type, overkillRatio)
				--spawn a nuke
				nuke(self:GetPosition());

				-- add points to player				
				local instArmy = instigator:GetArmy();
				local armyName = ArmyIndexer(GetArmyBrain(instArmy));
				LOG("___SE___ weapon killed, id="..self.myID.." instigator army: "..instArmy.."/"..armyName);
				killCount[armyName] = killCount[armyName] + 1;

				-- handle game logic
				numSpecialsOpen = numSpecialsOpen - 1;
				msgOut("Enemy weapon was destroyed by " .. getUsername(instArmy) .. "! "..numSpecialsOpen.. " weapons left.");
				specials[self.myID] = nil;
				LOG("___SE___ SPECIAL KILLED. iD="..self.myID);
				self.OldOnKilled(self, instigator, type, overkillRatio);
			end

			-- if it's a nuke, fill it with missiles and fire
			if (special == 'xsb2305' or special == 'xsb2401' or special == 'ueb2305' or special == 'urb2305' or special == 'uab2305') then
				specials[i].isNuke = true;
			end
		end
	end
end

-- checks if nuke launchers are present and fires them at the hill center
fireNukes = function()
	for i = 1,playercount do
		if (specials[i].isNuke == true) then
			specials[i]:GiveNukeSiloAmmo(5);
			IssueNuke( { specials[i] }, ScenarioUtils.MarkerToPosition( 'HILL_CENTER' ) );
		end
	end
end


gameLogic = function()
	-- check if all gates and specials were destroyed
	if (numGatesOpen < 1) then
		-- all gates down, display victory and end game
		for i, army in ListArmies() do
			if (army == "ARMY_1" or army == "ARMY_2" or army == "ARMY_3" or army == "ARMY_4" or
					army == "ARMY_5" or army == "ARMY_6" or army == "ARMY_7" or army == "ARMY_8") then
				GetArmyBrain(army):OnVictory();
			end
		end
		GetArmyBrain("ARMY_SURVIVAL_ENEMY"):OnDefeat();
		gameEnd = true;
	end
end

spawnThread = function(self)
	LOG("___SE___ Spawn thread running!");
	-- wait before starting the unit spam
	local startupTime = ScenarioInfo.Options.opt_startupTime;
	local now = 0;
	while (now < startupTime) do
		now = GetGameTimeSeconds();
		local rest = startupTime - now;
		if (rest < 0) then rest = 0; end
		Sync.ObjectiveTimer = math.floor(rest);
		WaitSeconds(1);
	end
	Sync.ObjectiveTimer = 0;

	msgOut("Attack waves have spawned!");
	--start sending the units
	while (gameEnd == false) do
		-- start at wave 1 in loop0
		if (loop == 0) then
			waveid = 1;
		else
			waveid = 40;
		end
		-- spawn the waves
		spawnWaves();
		-- next loop
		loop = loop + 1;
		loopEnd = false;
		-- at loop end spawn the special weapons, and wait 2 minutes
		if (gameEnd == false) then
			spawnSpecials();
			fireNukes();
			WaitSeconds(60*2);
		end
	end
	--no more waves to send, kill thread
	KillThread(self);
end


-- iterates through wavetable and calls unit spawn function
spawnWaves = function()
	while (loopEnd == false and gameEnd == false and numGatesOpen > 0) do
		--if the wave exists
		if (waveid > table.getn(waveTable)) then
			loopEnd = true;
			return;
		end

		LOG("___SE___ spawning base wave: " .. waveid);
		--spawn one wave per player
		for i = 1,playercount do
			-- randomly get a wave from the next 5 wavetable entries
			local waveBias = math.floor(waveid / 5) * 5;
			local waveMod = Utilities.GetRandomInt(1,5);
			local waveToSpawn = waveBias + waveMod;
			if (waveToSpawn > table.getn(waveTable)) then
				waveToSpawn = table.getn(waveTable);
			end
			LOG("___SE___ sending in wave number " .. waveToSpawn.." for player "..i);
			spawnWave(waveToSpawn);
		end

		--Sync.ObjectiveTimer = table.getn(waveTable)-waveid;
		if (math.mod(waveid, 10) == 0) then
			msgOut("Attack wave "..waveid.." has spawned!");
		end

		-- at a chance of 3 to 10, fire nukes from the silos
		if (Utilities.GetRandomInt(1,10) <= 3) then
			fireNukes();
		end

		--wait time until next wave
		local waitTime = ScenarioInfo.Options.opt_waveTime;
		WaitSeconds(waitTime);
		waveid = waveid+1;

	end
end

spawnWave = function()
	-- fetch wave data
	local wave = waveTable[waveid];
	-- end if end of wavetable reached
	if (wave == nil) 		then return; end
	-- if no more gates are open, do nothing
	if (numGatesOpen == 0)	then return; end
	for gateIndex = 1,8 do
		if (gates[gateIndex] == nil) then
			return;
		end
		spawnWaveAtGate(wave, gateIndex);
	end
end

spawnWaveAtGate = function(wave, gateIndex)
	local pos = ScenarioUtils.MarkerToPosition("Gate"..gateIndex);
	if (pos == nil) then
		LOG("___SE___ error: trying to spawn at nil gate");
		return;
	end
	-- create an empty array to combine spawned units to one platoon
	local platoonUnits = {};
	-- create a list of possible blueprint files we can to spawn
	local spawnList = createWaveSpawnList(wave);
	-- iterate through the blueprint-list we have just generated and spawn the units
	for index, bp in spawnList do
		doSpawnUnit(bp, pos, platoonUnits);
	end
	--give attack order
	startAttackMove(platoonUnits, gateIndex);
end

createWaveSpawnList = function(wave)
	-- create a list of possible blueprint files we can to spawn
	local spawnList = {};
	-- go through the techlevels, as described in the wave table
	-- table entry contains: 	{t1 = {10, 0}, t2 = {0,0} , t3 = {0, 0}, t4 = {0, 0}, t5 = {0, 0},},
	for techlevel = 1,5 do
		local numGroundAir = wave["t"..techlevel];
		local numGround = math.ceil(numGroundAir[1] * ScenarioInfo.Options.opt_difficulty);
		local numAir = math.ceil(numGroundAir[2] * ScenarioInfo.Options.opt_difficulty);

		-- loop modifier
		numGround = numGround * (loop+1);
		numAir = numAir * (loop+1);

		-- ground units
		local bpCount = table.getn(unitTableGround[techlevel]);
		for c = 1, numGround do
			local rr = Utilities.GetRandomInt(1, bpCount);
			table.insert(spawnList, unitTableGround[techlevel][rr]);
		end
		-- air units
		local bpCount = table.getn(unitTableAir[techlevel]);
		for c = 1, numAir do
			local rr = Utilities.GetRandomInt(1, bpCount);
			table.insert(spawnList, unitTableAir[techlevel][rr]);
		end
	end
	return spawnList;
end

-- does the actual spawning of a unit
doSpawnUnit = function(bp, pos, platoon)
	--calculate offset position of unit
	local xside = math.random(0,1);
	local yside = math.random(0,1);
	local xoff = -10 + xside*16 + math.random(0,1)*4;
	local yoff = -10 + yside*16 + math.random(0,1)*4;

	-- spawn unit
	local unit = CreateUnitHPR( bp, "ARMY_SURVIVAL_ENEMY", pos[1]+xoff, pos[2], pos[3]+yoff, 0,0,0);
	if (unit == nil) then
		return;
	end
	-- no wreckages after first round (to speed up game, can be removed when we all have quadcores/octacores ;=)
	if (loop > 0) then
		local bp = unit:GetBlueprint();
		if (bp != nil) then
	bp.Wreckage = nil; -- bp.Wreckage.WreckageLayers.Land=false;
		end
	end

	-- insert to platoon list
	table.insert(platoon, unit);

	-- check for upgrades
	local skip = Utilities.GetRandomInt(1, 4);
	if (skip != 3) then	-- one out of four commanders has no upgrades
	if (bp == "UAL0301") then		-- aeon
	local ucnt = table.getn(upgradeTable["A"]);
	local enh = upgradeTable["A"][Utilities.GetRandomInt(1, ucnt)];
	unit:CreateEnhancement(enh);
	elseif (bp == "URL0301") then	-- cybran
	local ucnt = table.getn(upgradeTable["R"]);
	local enh = upgradeTable["R"][Utilities.GetRandomInt(1, ucnt)];
	if (enh == 'StealthGenerator') then	-- stealth needs cloaking first, bug in game
	unit:CreateEnhancement('CloakingGenerator');
	end
	unit:CreateEnhancement(enh);
	elseif (bp == "UEL0301") then	-- uef
	local ucnt = table.getn(upgradeTable["E"]);
	local enh = upgradeTable["E"][Utilities.GetRandomInt(1, ucnt)];
	unit:CreateEnhancement(enh);
	elseif (bp == "xsl0301") then	-- seraphim
	local ucnt = table.getn(upgradeTable["S"]);
	local enh = upgradeTable["S"][Utilities.GetRandomInt(1, ucnt)];
	unit:CreateEnhancement(enh);
	end
	end

	--apply buffs based on  difficulty
	local difficultyBuff = ScenarioInfo.Options.opt_difficulty;
	unit:SetMaxHealth(unit:GetHealth()*difficultyBuff);
	unit:SetHealth(nil, unit:GetHealth()*difficultyBuff);
end


--forms a platoon to attack the hill with a given set of units
startAttackMove = function(units,pgate)
	local gate = pgate;
	if (table.getn(units) > 0) then
		local aiBrain = GetArmyBrain("ARMY_SURVIVAL_ENEMY");
		local attackPlatoon = aiBrain:MakePlatoon('','');
		local fcnt = table.getn(formationTable);
		local formation = formationTable[Utilities.GetRandomInt(1, fcnt)];
		aiBrain:AssignUnitsToPlatoon(attackPlatoon, units, 'Attack', formation);
		-- add a random waypoint
		-- old waypoint behaviour
		--local r = Utilities.GetRandomInt(1,8);
		--local waypointName = "WP"..r;
		--local posWP = ScenarioUtils.MarkerToPosition(waypointName);
		--attackPlatoon:AggressiveMoveToLocation(posWP);


		-- NEW  waypoint bevaiour	

		local l3 = 4
		local l2 = 3
		local l1 = 2
		local l0 = 1
		local waypointName;
		if(gate==8) then
			-- choose any of the 4
			waypointName = "WP"..l3;
			local posWP4 = ScenarioUtils.MarkerToPosition(waypointName);
			attackPlatoon:AggressiveMoveToLocation(posWP4);

		end
		if(gate==7) then
			-- choose any of the 4
			waypointName = "WP"..l3;
			local posWP4 = ScenarioUtils.MarkerToPosition(waypointName);
			attackPlatoon:AggressiveMoveToLocation(posWP4);

		end
		if(gate==5) then
			-- choose any of the 4
			waypointName = "WP"..l2;
			local posWP3 = ScenarioUtils.MarkerToPosition(waypointName);
			attackPlatoon:AggressiveMoveToLocation(posWP3);
		end
		if(gate==6) then
			-- choose any of the 4
			waypointName = "WP"..l2;
			local posWP3 = ScenarioUtils.MarkerToPosition(waypointName);
			attackPlatoon:AggressiveMoveToLocation(posWP3);
		end
		if(gate==3) then
			-- choose any of the 4
			waypointName = "WP"..l1;
			local posWP2 = ScenarioUtils.MarkerToPosition(waypointName);
			attackPlatoon:AggressiveMoveToLocation(posWP2);
		end
		if(gate==4) then
			-- choose any of the 4
			waypointName = "WP"..l1;
			local posWP2 = ScenarioUtils.MarkerToPosition(waypointName);
			attackPlatoon:AggressiveMoveToLocation(posWP2);
		end
		if(gate==1) then
			-- choose any of the 4
			waypointName = "WP"..l0;
			local posWP1 = ScenarioUtils.MarkerToPosition(waypointName);
			attackPlatoon:AggressiveMoveToLocation(posWP1);
		end
		if(gate==2) then
			-- choose any of the 4
			waypointName = "WP"..l0;
			local posWP1 = ScenarioUtils.MarkerToPosition(waypointName);
			attackPlatoon:AggressiveMoveToLocation(posWP1);
		end
		--local posCENTER = ScenarioUtils.MarkerToPosition('HILL_CENTER');
		attackPlatoon:Destroy();
	end
end


------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- misc funcs
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- spawn acu and kill it to create a fake nuke explosion :=) *hack hack hack, but the gpg devs said it's easiest way atm*
nuke = function(position)
	local acu = CreateUnitHPR( "ual0001", "ARMY_SURVIVAL_ENEMY", position[1], position[2], position[3], 0,0,0);
	if (acu != nil) then
	acu:Kill();
	end
end

-- kills all commanders of a specified army
killAllCommanders = function(army)
	local list = GetArmyBrain(army):GetListOfUnits(categories.COMMAND , false);
	for i, u in list do
		if (u:IsDead() == false) then
			u:Kill();
		end
	end
end


--given a player returns a proper username
getUsername = function(army)
	return GetArmyBrain(army).Nickname;
end

--given an ai brain returns an army index
function ArmyIndexer(aiBrain)
	local army = aiBrain:GetArmyIndex();
	for i, v in ListArmies() do
		if (i == army) then
			return v;
		end
	end
end

--given a player returns the number of kills
--armyKills = function(army)
--	local kills = GetArmyBrain(army):GetArmyStat('Enemies_Killed',0.0).Value;
--	return kills;
--end

armyKills = function(brain)
	local kills = brain:GetArmyStat('Enemies_Killed',0.0).Value;
	return kills;
end

-- display mm:ss instead of seconds
secondsToTime = function(seconds)
	return string.format("%02d:%02d", math.floor(seconds/60), math.mod(seconds, 60));
end

-- display a text message
msgOut = function(text, army)
	local color = nil;
	if (army != nil) then
	local colorIndex = ScenarioInfo.ArmySetup[army].PlayerColor;
	color = import('/lua/GameColors.lua').GameColors.ArmyColors[colorIndex];
	end
	PrintText(text, 20, color, 10, 'center') ;
end

--EOF
