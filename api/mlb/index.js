export default async function handler(req, res) {
  try {
    const response = await fetch(
      "https://site.web.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard"
    );

    const data = await response.json();

    const games = data.events.map(event => {
      const comp = event.competitions?.[0];
      if (!comp) return null;

      const home = comp.competitors.find(t => t.homeAway === "home");
      const away = comp.competitors.find(t => t.homeAway === "away");

      if (!home || !away) return null;

      // 🔥 Extract inning half
      const detail = event.status?.type?.detail || "";
      const lower = detail.toLowerCase();

      let inningHalf = null;

      if (lower.includes("top")) inningHalf = "top";
      else if (lower.includes("bottom")) inningHalf = "bottom";
      else if (lower.includes("mid")) inningHalf = "mid";
      else if (lower.includes("end")) inningHalf = "end";

      return {
        id: event.id,

        date: event.date,

        status: event.status.type.description,
        state: event.status.type.state, // "pre" | "in" | "post"

        clock: event.status.displayClock,

        period: {
          current: event.status.period, // inning number
          type: event.status.type.name,
          inningHalf,
          isHalftime: false
        },
        // 🔥 Optional nice display (can remove if not needed)
        inningDisplay:
          inningHalf && event.status.period
            ? `${inningHalf.charAt(0).toUpperCase() + inningHalf.slice(1)} ${event.status.period}`
            : null,

        homeTeam: {
          id: home.team.id,
          name: home.team.displayName,
          abbreviation: home.team.abbreviation,
          logo: home.team.logo,
          score: Number(home.score || 0)
        },

        awayTeam: {
          id: away.team.id,
          name: away.team.displayName,
          abbreviation: away.team.abbreviation,
          logo: away.team.logo,
          score: Number(away.score || 0)
        },

        venue: comp.venue?.fullName || null,

        broadcasts:
          comp.broadcasts?.map(b => b.names?.[0]).filter(Boolean) || [],

        gameLink: event.links?.[0]?.href || null
      };
    }).filter(Boolean);

    res.setHeader("Access-Control-Allow-Origin", "*");
    res.status(200).json(games);

  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "failed to fetch mlb games" });
  }
}