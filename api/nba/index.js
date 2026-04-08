export default async function handler(req, res) {
    try {
        const response = await fetch(
            "https://site.web.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"
        );

        const data = await response.json();

        const games = data.events.map(event => {
            const comp = event.competitions[0];
            const home = comp.competitors.find(t => t.homeAway === "home");
            const away = comp.competitors.find(t => t.homeAway === "away");

            return {
                id: event.id,

                date: event.date,
                
                status: event.status.type.description,
                clock: event.status.displayClock,
                period: {
                    current: event.status.period, // 1,2,3,4,5...
                    type: event.status.type.name === "STATUS_OVERTIME" ? "OT" : "REG",
                    isHalftime: event.status.type.description === "Halftime"
                },

                homeTeam: {
                    id: home.team.id,
                    name: home.team.displayName,
                    abbreviation: home.team.abbreviation,
                    logo: home.team.logo,
                    score: Number(home.score)
                },

                awayTeam: {
                    id: away.team.id,
                    name: away.team.displayName,
                    abbreviation: away.team.abbreviation,
                    logo: away.team.logo,
                    score: Number(away.score)
                },

                venue: comp.venue?.fullName,

                broadcasts: comp.broadcasts?.map(b => b.names?.[0]),

                gameLink: event.links?.[0]?.href || null
            };
        });

        res.setHeader("Access-Control-Allow-Origin", "*");
        res.status(200).json(games);

    } catch (err) {
        console.error(err);
        res.status(500).json({ error: "failed" });
    }
}