# Car bodies

Mesh bodies in `ServerStorage.CarBodies`, one model per vehicle, named after its Config.Vehicles id.
CarBuilder swaps the greybox shell for the model with the same name; BodyPrep makes them (see the
header comments in `src/server/Tools/CarBuilder.lua` and `src/server/Tools/BodyPrep.lua`).

Rebuilt on 2026-10-19 from the MeshId / TextureID values in NeonCoast.rbxl (Sep 28 save).
The original version of this file was lost; anything else it held is not in the place file.

(An earlier note here described a `Hull = { Turn, Size }` fix for sideways boat hulls. That was for an
older place: in the current NeonCoast.rbxl every hull already lies along Z (Splash 4.6 x 4.4 x 11,
HarborPatrol turned in its template to 9.5 x 13 x 22) and Config.Vehicles has no `Hull` field.)

## Seats (2026-10-26)

How the seats are placed is in the header of `src/server/Tools/CarBuilder.lua` (fitSeats). Hand-tuned
seats live as template attributes and, as a copy, on the car's Config.Vehicles entry:

| Car | Seat values | Why |
|---|---|---|
| Gatorback | SeatDrop -1.35, SeatTilt 6, SeatZ 0.9 (template + config) | open roll cage, was driving from the bed |
| Sandpiper | SeatDrop -0.35 | buggy: hair under the top bar |
| Flamingo | SeatDrop -0.5 | convertible: shoulders above the doors |
| SolanaGT, Riptide | SeatTilt 40 (template + config) | low roofs |
| Vortex | SeatTilt 40 (config only) | low roof |
| RiotTruck, ArmoredVan | SeatDrop -0.7, SeatZ -0.6 (config only) | the auto fit sat the driver low and 2 studs back, hidden in the box: now up in the cab, head mid-windscreen |
| Splash | SeatY 1, SeatZ 1.3 (template) | the saddle |
| HarborPatrol | SeatY 3.4, SeatZ -0.5 (config only, estimated) | the old spot was inside the 13-stud hull |
| Moonstone | SeatY 4.5, SeatZ 7 (config only, estimated) | the old spot was inside the 16-stud hull; now the aft deck |

Every other closed car is fitted automatically (head mid-window, leaned back up to 30 degrees so a
standard R15 head plus 0.9 studs of hair stays under the glass top). On top of that each rider is fitted
to their own size when they sit down (CarBuilder.FitRider, seat attributes HeadRoom / FloorRoom /
Recline): a taller avatar or a hat that would reach through the roof sinks into the seat and leans back
(45 degrees at most). VehicleFeel leans the riders with the body, so the roof no longer dips onto still
heads in a hard stop or over a kerb.

Check them in Studio: Play, then in the server command bar
`require(game.ServerStorage.Tools.CarBuilder).Showroom(Vector3.new(0, 40, 0))` (add `, 1.3` for tall
avatars) builds every vehicle in a row with an R15 dummy in every seat. `Showroom(nil)` clears it. A seat
that looks wrong: set SeatDrop / SeatZ / SeatTilt (boats: SeatY / SeatZ) as attributes on the template
in ServerStorage.CarBodies, run the showroom again, then copy the numbers into Config.Vehicles.

## Flamingo

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://78896108310304` | `rbxassetid://138687671976241` |
| Windows | `rbxassetid://72448867844759` | `rbxassetid://107938947675227` |
| Headlight | `rbxassetid://73219393283038` | `rbxassetid://120490679450883` |
| Taillight | `rbxassetid://105328289532259` | `rbxassetid://132694829183553` |
| Trim | `rbxassetid://137225238520685` | `rbxassetid://111359102519969` |
| Wheels | `rbxassetid://127995396695315` | `rbxassetid://97004387603367` |

## Gatorback

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://133422789164591` | `rbxassetid://105270478346526` |
| Windows | `rbxassetid://119348300935092` | `rbxassetid://84222753547304` |
| Headlight | `rbxassetid://108906782762580` | `rbxassetid://133540803566809` |
| Taillight | `rbxassetid://86215396334893` | `rbxassetid://137241907292160` |
| Trim | `rbxassetid://110290148528588` | `rbxassetid://128552369301163` |
| Wheels | `rbxassetid://123911789143860` | `rbxassetid://130143864714428` |

## HarborPatrol

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://101353033713262` | `rbxassetid://131981654210618` |

## Mangrove

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://125889648166643` | `rbxassetid://114383648836044` |
| Windows | `rbxassetid://98732461128842` | `rbxassetid://98571783835231` |
| Headlight | `rbxassetid://139836243700607` | `rbxassetid://84591383167094` |
| Taillight | `rbxassetid://115007836744242` | `rbxassetid://95541566775801` |
| Trim | `rbxassetid://120994065532707` | `rbxassetid://125929323215689` |
| Wheels | `rbxassetid://95052365432084` | `rbxassetid://136672734599624` |

## Marlin

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://125429693119325` | `rbxassetid://138516096190960` |

## NightHeron

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://113534357529051` | `rbxassetid://122954077206985` |
| Windows | `rbxassetid://129298409182953` | `rbxassetid://71100048506644` |
| Headlight | `rbxassetid://81840577904333` | `rbxassetid://108001484767583` |
| Taillight | `rbxassetid://75853435922473` | `rbxassetid://92921246153352` |
| Trim | `rbxassetid://89852642562298` | `rbxassetid://104995304674790` |
| Wheels | `rbxassetid://86868451938263` | `rbxassetid://136029555257145` |

## Palmetto

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://87726346090893` | `rbxassetid://116744497467613` |
| Windows | `rbxassetid://104477900553598` | `rbxassetid://100939282473755` |
| Headlight | `rbxassetid://104632289729229` | `rbxassetid://131104267347369` |
| Taillight | `rbxassetid://121852886013380` | `rbxassetid://115428067335508` |
| Trim | `rbxassetid://85129094127443` | `rbxassetid://82802190222081` |
| Wheels | `rbxassetid://120015930626896` | `rbxassetid://110445566531282` |

## PursuitSpecial

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://100902847426180` | `rbxassetid://123762554607334` |
| Windows | `rbxassetid://85899637728782` | `rbxassetid://90948377215807` |
| Headlight | `rbxassetid://92435100660670` | `rbxassetid://104342447898703` |
| Taillight | `rbxassetid://140583228842621` | `rbxassetid://104453179272507` |
| Trim | `rbxassetid://137936186526008` | `rbxassetid://89665844310142` |
| Wheels | `rbxassetid://78317533579700` | `rbxassetid://86680633299875` |

## RiotTruck

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://72770399010902` | `rbxassetid://112434064390673` |
| Windows | `rbxassetid://72781438489650` | `rbxassetid://115385704454171` |
| Headlight | `rbxassetid://136191567649863` | `rbxassetid://81276921273524` |
| Taillight | `rbxassetid://135591460708389` | `rbxassetid://109313407481791` |
| Trim | `rbxassetid://101991210732539` | `rbxassetid://124347999805924` |
| Wheels | `rbxassetid://87909570108383` | `rbxassetid://73619917541468` |

## Sandpiper

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://103976663892702` | `rbxassetid://112570822314700` |
| Windows | `rbxassetid://74150184192581` | `rbxassetid://124755699525363` |
| Headlight | `rbxassetid://124998546512385` | `rbxassetid://94520026366183` |
| Taillight | `rbxassetid://80355510206898` | `rbxassetid://85519036803831` |
| Trim | `rbxassetid://79974952416059` | `rbxassetid://95421308512487` |
| Wheels | `rbxassetid://139434251225188` | `rbxassetid://131836814940286` |

## SolanaGT

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://87103906015906` | `rbxassetid://121270086532330` |
| Windows | `rbxassetid://121662347472037` | `rbxassetid://94675888902979` |
| Headlight | `rbxassetid://123794655145603` | `rbxassetid://87256271786164` |
| Taillight | `rbxassetid://110992510993314` | `rbxassetid://99396311866606` |
| Trim | `rbxassetid://77232526666336` | `rbxassetid://125174807936168` |
| Wheels | `rbxassetid://131191110036175` | `rbxassetid://99372688747694` |

## Splash

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://103496046403795` | `rbxassetid://138083409864200` |

## SunrayPatrol

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://75545095164071` | `rbxassetid://133452346277762` |
| Windows | `rbxassetid://120314988140186` | `rbxassetid://76102025353597` |
| Headlight | `rbxassetid://133950856672400` | `rbxassetid://117522467604596` |
| Taillight | `rbxassetid://131620919966251` | `rbxassetid://90058854559763` |
| Trim | `rbxassetid://81631928084374` | `rbxassetid://94412567093730` |
| Wheels | `rbxassetid://89755520175736` | `rbxassetid://93278286416040` |

## Voltline

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://106670532774611` | `rbxassetid://99482194365281` |
| Windows | `rbxassetid://92839481748997` | `rbxassetid://93873882395532` |
| Headlight | `rbxassetid://136593566189496` | `rbxassetid://135893476202844` |
| Taillight | `rbxassetid://89285399349765` | `rbxassetid://127239672301034` |
| Trim | `rbxassetid://130307465968468` | `rbxassetid://90288685625777` |
| Wheels | `rbxassetid://82480760816772` | `rbxassetid://128262951611736` |

## Vortex

| Part | MeshId | TextureID |
|---|---|---|
| Body | `rbxassetid://101582195148425` | `rbxassetid://112451529406169` |
| Windows | `rbxassetid://134721520778064` | `rbxassetid://115350204395365` |
| Headlight | `rbxassetid://72101382769895` | `rbxassetid://126885401923851` |
| Taillight | `rbxassetid://138145818734532` | `rbxassetid://126528147038041` |
| Trim | `rbxassetid://87233548650795` | `rbxassetid://106203188083713` |
| Wheels | `rbxassetid://74995258931334` | `rbxassetid://102492716610571` |
