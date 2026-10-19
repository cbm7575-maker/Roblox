-- PedLines (ModuleScript, ReplicatedStorage.Shared.Config.PedLines)
-- Short speech-bubble lines for pedestrians (PedClient). One list per situation; PedClient picks a
-- random line from the list that fits what's happening. Keep them short (they show in a bubble for
-- a few seconds), kid-safe, silly and Florida-flavoured. Original lines only: no real people,
-- brands or other games.

local PedLines = {}

-- Running away from a wanted player or a speeding car.
PedLines.Panic = {
	"Not my smoothie! RUN!",
	"Nope nope nope!",
	"Third car chase this week!",
	"I just got these sandals!",
	"Somebody call my mom!",
	"I'm too sunburnt for this!",
	"Every gator for itself!",
	"This is NOT the beach day I planned!",
	"Ahh! My flip-flops!",
	"I left my iced tea back there!",
}

-- A police siren close by.
PedLines.Siren = {
	"Ooh, sirens. Somebody's in trouble.",
	"Wasn't me! I was at the beach!",
	"Go get 'em, officer!",
	"Another chase on Ocean Drive?",
	"Somebody forgot to signal again.",
	"I'll tell the whole group chat.",
}

-- A car only just missed them.
PedLines.Dodge = {
	"Hey! Sidewalks are for walking!",
	"Watch it, speed racer!",
	"Whoa! Nice reflexes, me!",
	"I'm telling the flamingos!",
	"Who gave you a license?",
}

-- Florida downpour.
PedLines.Rain = {
	"Five minutes of monsoon, then sunshine. Classic.",
	"My hair! I just got it done!",
	"Who needs a pool when it rains like this?",
	"Free car wash, everybody!",
	"The gators love this weather.",
	"Forgot my umbrella. Again.",
}

-- After dark, under the neon.
PedLines.Night = {
	"The neon makes everything look cooler.",
	"Night breeze! Finally!",
	"Is the Ferris wheel still open?",
	"Late-night tacos? Late-night tacos.",
	"The city really glows tonight.",
	"Shh, the gators are sleeping.",
}

-- Everyday chatter.
PedLines.Idle = {
	"Another perfect day in Port Solana.",
	"Did you see that pelican steal a sandwich?",
	"SPF 50 and still burnt.",
	"My grandma speed-walks faster than traffic.",
	"I saw a gator at the store again.",
	"Beach later? Beach later.",
	"Is it hot or is it just Florida?",
	"I heard there's treasure on Flamingo Beach.",
	"I'm on island time today.",
	"Key lime pie for breakfast. Don't judge.",
	"Somebody parked a boat in the drive-thru.",
	"I love the smell of sunscreen in the morning.",
}

-- Sitting at a bus stop, on a bench or a lounger.
PedLines.Sit = {
	"The bus is late. The bus is always late.",
	"Best seat in town.",
	"Just resting my flip-flops.",
	"I could sit here all day. I might.",
	"Ahh, shade.",
}

-- A player's customised or expensive car rolls past.
PedLines.NiceCar = {
	"Whoa, nice ride!",
	"Now THAT is a beach cruiser!",
	"Is that paint job real?",
	"I want that car. I want it so bad.",
	"Sweet wheels!",
	"Somebody's been saving up!",
}

-- Spectators at the Neon Nights car meet.
PedLines.CarMeet = {
	"That glow kit is unreal!",
	"I'm voting for the pink one.",
	"Rev it! Rev it!",
	"Best car meet on the coast!",
	"Look at those rims!",
	"Take a picture, take a picture!",
}

-- Florida moments (EventService): the street performer, the beach party, the lost tourist.
PedLines.Performer = {
	"Thank you, thank you!",
	"Tips keep the music going!",
	"This next one's for the gators!",
	"Port Solana, make some noise!",
}
PedLines.Party = {
	"Best beach party ever!",
	"Dance like nobody's watching!",
	"Who brought the glow sticks?",
	"The DJ is a seagull? Love it.",
}
PedLines.Tourist = {
	"Excuse me, where's the beach?",
	"Is this the way to the Ferris wheel?",
	"My map is upside down, isn't it?",
	"Do the gators bite? Asking for me.",
}

return PedLines
