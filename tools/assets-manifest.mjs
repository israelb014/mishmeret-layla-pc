// Source manifest for the asset pipeline. Every entry is CC0 (see CREDITS.md).
const RAW = '/home/one/work/raw';
const K = (pack, name, fmt = 'GLB') => `${RAW}/x/kenney/${pack}/Models/${fmt} format/${name}.glb`;
const DCK = name => `${RAW}/dck/${name}.gltf`;
const CONV = name => `${RAW}/conv/${name}.glb`;
const PP = name => `${RAW}/pp/${name}.glb`;

// Characters: Quaternius Ultimate Modular Men/Women + Animated Woman (via poly.pizza mirror)
export const CHARACTERS = {
  casual: PP('kZ3DmIoGip'), punk: PP('BTALZymknF'), punkf: PP('djXoqejw6w'), swat: PP('Btfn3G5Xv4'),
  worker: PP('Yg2bQZO6Hj'), suit: PP('JFrLIKqvCH'), beach: PP('DojKLcO34E'), woman: PP('nIItLV9nxS'),
  farmer: PP('7pn3R6hPvE'), adventurer: PP('5EGWBMpuXq'),
};
export const ANIM_SOURCE = PP('kZ3DmIoGip');

// Prefab libraries: lib name -> { sceneName: sourceFile }
export const LIBS = {
  city: {
    bld_large: DCK('Building_Large_2'), bld_medium: DCK('Building_Medium_2_001'), bld_small: DCK('Building_Small_1'),
    ac_unit: DCK('Prop_ACUnit'), planter: DCK('Prop_Planter_Single'), bollard: DCK('Prop_Bollard'), manhole: DCK('Prop_ManholeCover'),
    traffic_light: K('city-kit-roads', 'traffic-light'), lamp_curved: K('city-kit-roads', 'light-curved'), lamp_square: K('city-kit-roads', 'light-square'),
    dumpster: K('city-kit-roads', 'dumpster'), sign_post: K('city-kit-roads', 'road-sign-empty'), sign_hanging: K('city-kit-roads', 'road-sign-empty-hanging'),
    elec_pole: K('city-kit-roads', 'electricity-pole'), barrier_road: K('city-kit-roads', 'road-side-barrier'),
    awning: K('city-kit-commercial', 'detail-awning'), awning_wide: K('city-kit-commercial', 'detail-awning-wide'),
    parasol_a: K('city-kit-commercial', 'detail-parasol-a'), parasol_b: K('city-kit-commercial', 'detail-parasol-b'), overhang: K('city-kit-commercial', 'detail-overhang-wide'),
    fence: K('city-kit-suburban', 'fence-1x4'), fence_low: K('city-kit-suburban', 'fence-low'), tree_large: K('city-kit-suburban', 'tree-large'), tree_small: K('city-kit-suburban', 'tree-small'),
    fruit_stand: K('mini-market', 'display-fruit'), bread_stand: K('mini-market', 'display-bread'), shelf_boxes: K('mini-market', 'shelf-boxes'), cart: K('mini-market', 'shopping-cart'),
    balcony: K('retro-urban-kit', 'balcony-type-a'), scaffold: K('retro-urban-kit', 'scaffolding-structure'), scaffold_floor: K('retro-urban-kit', 'scaffolding-floor'),
    scaffold_poles: K('retro-urban-kit', 'scaffolding-poles'), barrier: K('retro-urban-kit', 'detail-barrier-strong-type-a'), pallet: K('retro-urban-kit', 'pallet-small'),
    dumpster_open: K('retro-urban-kit', 'detail-dumpster-open'), cables: K('retro-urban-kit', 'detail-cables-type-a'),
    palm: K('nature-kit', 'tree_palmDetailedTall', 'GLTF'), palm_short: K('nature-kit', 'tree_palm', 'GLTF'), tree_round: K('nature-kit', 'tree_default', 'GLTF'), bush: K('nature-kit', 'plant_bushLarge', 'GLTF'),
    barrel: K('survival-kit', 'barrel'), box: K('survival-kit', 'box'), box_large: K('survival-kit', 'box-large'), bottle: K('survival-kit', 'bottle'), bottle_large: K('survival-kit', 'bottle-large'), bucket: K('survival-kit', 'bucket'),
    potted_plant: K('furniture-kit', 'pottedPlant', 'GLTF'), plant_small: K('furniture-kit', 'plantSmall1', 'GLTF'), bin_small: K('furniture-kit', 'trashcan', 'GLTF'),
    solar_panel: K('city-kit-industrial', 'solar-panel-flat'), water_tank: K('city-kit-industrial', 'detail-tank'),
    cone: K('car-kit', 'cone'), crate_k: K('blaster-kit', 'crate-medium'), crate_wide: K('blaster-kit', 'crate-wide'),
    bench: PP('p_Bench'), red_barrel: PP('p_ExplodingBarrel'), trashcan: PP('p_Trashcan'), trash_container: PP('p_TrashContainerOpen'),
    trash_bags: PP('p_TrashBags'), water_bottle: PP('p_WaterBottle'), pickup_crate: PP('p_PickupCrate'), crate: PP('p_CubeCrate'), street_light: PP('p_StreetLight'),
    vending: CONV('Vending Machines'), traffic_light_q: CONV('TrafficLight'),
  },
  vehicles: {
    car_cop: CONV('Cop'), car_sedan: CONV('NormalCar1'), car_hatch: CONV('NormalCar2'), car_sport: CONV('SportsCar'), car_sport2: CONV('SportsCar2'),
    car_suv: CONV('SUV'), car_taxi: CONV('Taxi'), bus: CONV('Bus'), van: K('car-kit', 'van'), delivery: K('car-kit', 'delivery'), truck_k: K('car-kit', 'truck'),
    truck_box: CONV('truck_02'), garbage: K('car-kit', 'garbage-truck'), loader: K('car-kit', 'tractor-shovel'), wheel: K('car-kit', 'wheel-default'),
  },
  port: {
    cont_a: K('city-kit-industrial', 'shipping-container-a'), cont_b: K('city-kit-industrial', 'shipping-container-b'), cont_c: K('city-kit-industrial', 'shipping-container-c'),
    cont_q: PP('p_ContainerGreen'),
    ship_cargo: K('watercraft-kit', 'ship-cargo-a'), ship_cargo_b: K('watercraft-kit', 'ship-cargo-b'), ship_large: K('watercraft-kit', 'ship-large'), tug: K('watercraft-kit', 'boat-tug-a'),
    buoy: K('watercraft-kit', 'buoy'), cargo_pile: K('watercraft-kit', 'cargo-pile-a'), boat: K('watercraft-kit', 'boat-fishing-small'),
    crane_k: K('factory-kit', 'crane'), struct_tall: K('factory-kit', 'structure-yellow-tall'), struct_high: K('factory-kit', 'structure-yellow-high'),
    catwalk: K('factory-kit', 'catwalk-junction'), catwalk_stairs: K('factory-kit', 'catwalk-stairs'), box_factory: K('factory-kit', 'box-large'), warning: K('factory-kit', 'warning-orange'),
    tank_large: K('city-kit-industrial', 'detail-tank-large'), chimney: K('city-kit-industrial', 'chimney-large'), warehouse_a: K('city-kit-industrial', 'building-a'),
    warehouse_b: K('city-kit-industrial', 'building-c'), warehouse_c: K('city-kit-industrial', 'building-g'), water_tower: K('city-kit-industrial', 'water-tower'),
  },
  station: {
    train_city: K('train-kit', 'train-electric-city-b'), train_city_a: K('train-kit', 'train-electric-city-a'), tram: K('train-kit', 'train-tram-classic'),
    track: K('train-kit', 'track-single-detailed'), rail: K('train-kit', 'railroad-straight'), train_q: CONV('Train'),
    ticket: K('space-station-kit', 'computer-system'), rail_guard: K('space-station-kit', 'balcony-rail'), stairs_rail: K('space-station-kit', 'stairs-handrail'),
    pillar: DCK('Metal_Column_Center'), bench_metal: K('space-station-kit', 'chair-armrest'), display: K('space-station-kit', 'display-wall-wide'),
    stairs: K('building-kit', 'stairs-closed'), flatbed: K('train-kit', 'train-carriage-flatbed'), wagon: K('train-kit', 'train-carriage-container-blue'),
    loco: K('train-kit', 'train-locomotive-passenger-b'),
  },
  weapons: {
    pistol: CONV('Pistol_1'), pistol_b: CONV('Pistol_3'), revolver: CONV('Revolver_1'), shotgun: CONV('Shotgun_ShortStock'),
    smg: CONV('SubmachineGun_1'), smg_b: CONV('SubmachineGun_3'), knife: CONV('knife'), grenade: `${RAW}/oga/mk2-grenade/x/mk2_grenade.glb`,
  },
};

// Poly Haven texture sets (1K): name -> source folder
export const TEXTURES = {
  asphalt: 'asphalt_02', pavers: 'concrete_pavers_02', limestone: 'large_sandstone_blocks', plaster: 'plastered_wall_02',
  concrete: 'concrete_wall_008', brick: 'brick_wall_02', corrugated: 'corrugated_iron_02', planks: 'brown_planks_05',
  deck: 'metal_plate', tiles: 'floor_tiles_08', facade_tiles: 'rectangular_facade_tiles', shutter: 'painted_metal_shutter',
};
export const HDRIS = { afternoon: 'kloofendal_43d_clear_puresky', sunset: 'qwantani_sunset_puresky', night: 'rooftop_night' };

const SFX = `${RAW}/sfx`;
const FL = `${SFX}/the-free-firearm-sound-library/x/Prepared SFX Library`;
const KA = (pack, f) => `${RAW}/x/kenney/${pack}/Audio/${f}`;
// out name -> [source, options]
export const SOUNDS = {
  pistol: [`${FL}/Walther PPQ`, { pick: 0, dur: 0.9 }], mpistol: [`${FL}/PPSh`, { pick: 0, dur: 0.35 }], shotgun: [`${FL}/Mossberg`, { pick: 0, dur: 1.2 }],
  magnum: [`${FL}/Ruger Single Six`, { pick: 0, dur: 1.4 }], enemy_shot: [`${FL}/Bersa`, { pick: 0, dur: 0.9, vol: 0.8 }],
  boss_mg: [`${FL}/AK-47`, { pick: 0, dur: 0.3 }],
  reload: [`${SFX}/gun-reload-sounds/gunreload1.wav`, { dur: 0.7 }], click: [`${SFX}/100-cc0-sfx/x/switch_01.ogg`, {}],
  ricochet: [KA('impact-sounds', 'impactMetal_light_002.ogg'), { pitch: 1.9 }], glass: [`${SFX}/75-cc0-breaking-falling-hit-sfx/x/bfh1_glass_breaking_03.ogg`, {}],
  glass2: [`${SFX}/glass-break/glass_breaking.wav`, { dur: 1.5 }], metal: [KA('impact-sounds', 'impactMetal_medium_001.ogg'), {}],
  wood: [KA('impact-sounds', 'impactWood_medium_002.ogg'), {}], hit_body: [KA('impact-sounds', 'impactPunch_medium_001.ogg'), {}],
  explosion: [`${SFX}/100-cc0-sfx/x/explosion.ogg`, {}], explosion2: [KA('sci-fi-sounds', 'explosionCrunch_000.ogg'), {}],
  hurt: [`${SFX}/15-vocal-male-strainhurtpainjump-sounds/x/slightscream-04.flac`, {}], scream: [`${SFX}/female-scream-1/female_scream_1.ogg`, { dur: 1.6 }],
  scream2: [`${SFX}/female-hurt-grunts-groans/female_hurt_grunts_groans_1.ogg`, { start: 0, dur: 1.0 }],
  siren: [`${SFX}/sirens-and-alarm-noise/siren_0.mp3`, { dur: 6 }], engine: [`${SFX}/car-sound-effects-pack-low-quality/x/Car_Engine_Loop.ogg`, {}],
  screech: [`${SFX}/stk/sfx kart game_0.mp3`, { start: 72.6, dur: 2.2 }], ui_click: [KA('interface-sounds', 'click_002.ogg'), {}],
  ui_hover: [KA('interface-sounds', 'tick_001.ogg'), { vol: 0.5 }], zone_clear: [KA('music-jingles', 'Pizzicato jingles/jingles_PIZZI10.ogg'), {}],
  stage_clear: [KA('music-jingles', 'Steel jingles/jingles_STEEL16.ogg'), {}], pickup: [KA('interface-sounds', 'confirmation_002.ogg'), {}],
  shield: [KA('interface-sounds', 'maximize_006.ogg'), {}], empty: [`${SFX}/100-cc0-sfx/x/switch_02.ogg`, { vol: 0.9 }],
  grenade_bounce: [KA('impact-sounds', 'impactMetal_light_000.ogg'), {}], knife: [KA('impact-sounds', 'impactPlate_light_001.ogg'), {}],
  thud: [KA('impact-sounds', 'impactSoft_heavy_001.ogg'), {}], bottle: [KA('impact-sounds', 'impactGlass_light_002.ogg'), {}],
  sign: [KA('impact-sounds', 'impactPlate_medium_002.ogg'), {}], tire: [KA('impact-sounds', 'impactSoft_medium_003.ogg'), { pitch: 0.6 }],
  alarm: [KA('sci-fi-sounds', 'computerNoise_001.ogg'), {}], train: [`${SFX}/racing-car-engine-sound-loops/loop_0.wav`, { pitch: 0.5 }],
};
const MUS = `${RAW}/music`;
export const MUSIC = {
  menu: [`${MUS}/menu-music.wav`, { loop: true }], stage1: [`${MUS}/action-track.mp3`, { loop: true }], stage2: [`${MUS}/the-rush.mp3`, { loop: true }],
  stage3: [`${MUS}/night-prowler.ogg`, { loop: true }], boss: [`${MUS}/boss-battle-music.wav`, { loop: false }], results: [`${MUS}/winning-the-race.ogg`, { loop: true }],
};
