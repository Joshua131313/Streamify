// import axios from "axios";
// import * as cheerio from "cheerio";

// const ONE_DAY = 24 * 60 * 60 * 1000;

// let cache = null;
// let cacheTime = 0;

// const NBA_TEAM_IDS = {
//   "Atlanta Hawks": "1610612737",
//   "Boston Celtics": "1610612738",
//   "Brooklyn Nets": "1610612751",
//   "Charlotte Hornets": "1610612766",
//   "Chicago Bulls": "1610612741",
//   "Cleveland Cavaliers": "1610612739",
//   "Dallas Mavericks": "1610612742",
//   "Denver Nuggets": "1610612743",
//   "Detroit Pistons": "1610612765",
//   "Golden State Warriors": "1610612744",
//   "Houston Rockets": "1610612745",
//   "Indiana Pacers": "1610612754",
//   "Los Angeles Clippers": "1610612746",
//   "Los Angeles Lakers": "1610612747",
//   "Memphis Grizzlies": "1610612763",
//   "Miami Heat": "1610612748",
//   "Milwaukee Bucks": "1610612749",
//   "Minnesota Timberwolves": "1610612750",
//   "New Orleans Pelicans": "1610612740",
//   "New York Knicks": "1610612752",
//   "Oklahoma City Thunder": "1610612760",
//   "Orlando Magic": "1610612753",
//   "Philadelphia 76ers": "1610612755",
//   "Phoenix Suns": "1610612756",
//   "Portland Trail Blazers": "1610612757",
//   "Sacramento Kings": "1610612758",
//   "San Antonio Spurs": "1610612759",
//   "Toronto Raptors": "1610612761",
//   "Utah Jazz": "1610612762",
//   "Washington Wizards": "1610612764"
// };

// function getLogo(team) {
//   const id = NBA_TEAM_IDS[team];
//   if (!id) return null;

//   return `https://cdn.nba.com/logos/nba/${id}/global/L/logo.svg`;
// }

// export default async function handler(req, res) {
//   try {
//     // ✅ cache
//     if (cache && Date.now() - cacheTime < ONE_DAY) {
//       return res.status(200).json(cache);
//     }

//     const response = await axios.get(
//       "https://sharkstreams.net/category/nba",
//       {
//         headers: {
//           "User-Agent": "Mozilla/5.0"
//         }
//       }
//     );

//     const $ = cheerio.load(response.data);

//     const games = [];

//     $(".row").each((i, el) => {
//       const dateRaw = $(el).find(".ch-date").text().trim();
//       const game = $(el).find(".ch-name").text().trim();
//       const watch = $(el).find(".hd-link").first().attr("onclick");

//       const isoDate = dateRaw.replace(" ", "T")


//       // ✅ simple logic
//       let stream = null;

//       if (watch) {
//         const match = watch.match(/'(https:\/\/[^']+)'/);
//         if (match) stream = match[1];
//       }
//       let channel = null;
//       let streamProvider = null;

//       if (stream) {
//         // extract channel
//         const channelMatch = stream.match(/channel=(\d+)/);
//         if (channelMatch) {
//           channel = channelMatch[1];
//         }

//         // extract domain (stream type)
//         try {
//           const url = new URL(stream);
//           streamProvider = url.hostname.replace("www.", "").split(".")[0];
//         } catch {
//           streamProvider = null;
//         }
//       }

//       if (game) {
//         const [homeTeam, awayTeam] = game.split(" vs ");

//         games.push({
//           date: isoDate,
//           game,
//           stream,
//           channel,
//           streamProvider,
//           homeTeam: {
//             name: homeTeam,
//             logo: getLogo(homeTeam.trim())
//           },
//           awayTeam: {
//             name: awayTeam,
//             logo: getLogo(awayTeam.trim())
//           }
//         });
//       }
//     });

//     cache = games;
//     cacheTime = Date.now();

//     return res.status(200).json(games);

//   } catch (err) {
//     console.error("SCRAPE ERROR:", err);
//     return res.status(500).json({ error: "scrape failed" });
//   }
// }


import axios from "axios";
import * as cheerio from "cheerio";

const CACHE_TIME = 1000 * 60 * 2; // 2 min

let cache = null;
let cacheTime = 0;

const normalize = (name) =>
  name.toLowerCase().replace(/[^a-z]/g, "");

export default async function handler(req, res) {
  try {
    if (cache && Date.now() - cacheTime < CACHE_TIME) {
      return res.status(200).json(cache);
    }

    // 🔥 FETCH BOTH
    const [espnRes, scrapedRes] = await Promise.all([
      axios.get(
        "https://site.web.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"
      ),
      axios.get("https://sharkstreams.net/category/nba", {
        headers: { "User-Agent": "Mozilla/5.0" }
      })
    ]);

    // 🔥 SCRAPER MAP
    const $ = cheerio.load(scrapedRes.data);
    const scraperMap = {};

    $(".row").each((_, el) => {
      const game = $(el).find(".ch-name").text().trim();
      const watch = $(el).find(".hd-link").first().attr("onclick");

      if (!game) return;

      const [away, home] = game.split(" vs "); // ✅ FIXED ORDER

      const key = normalize(away) + "_" + normalize(home);

      let stream = null;
      let channel = null;
      let streamProvider = null;

      if (watch) {
        const match = watch.match(/'(https:\/\/[^']+)'/);
        if (match) stream = match[1];
      }

      if (stream) {
        const channelMatch = stream.match(/channel=(\d+)/);
        if (channelMatch) channel = channelMatch[1];

        try {
          const url = new URL(stream);
          streamProvider = url.hostname.replace("www.", "").split(".")[0];
        } catch { }
      }

      scraperMap[key] = { stream, channel, streamProvider };
    });

    // 🔥 BUILD FINAL DATA FROM ESPN
    const games = espnRes.data.events.map(event => {
      const competitors = event.competitions[0].competitors;

      const home = competitors.find(t => t.homeAway === "home");
      const away = competitors.find(t => t.homeAway === "away");

      const homeName = home.team.displayName;
      const awayName = away.team.displayName;

      const key = normalize(awayName) + "_" + normalize(homeName);

      const streamData = scraperMap[key];

      return {
        id: event.id,

        // ⏱ time
        date: event.date,
        startTimeUTC: event.date,

        // 📊 status
        status: event.status.type.description,
        rawStatus: event.status.type.description,
        clock: event.status.displayClock,

        // 🏟 venue
        venue: {
          name: event.competitions[0].venue?.fullName,
          city: event.competitions[0].venue?.address?.city,
          state: event.competitions[0].venue?.address?.state
        },

        // 🏀 teams
        homeTeam: {
          id: home.team.id,
          name: home.team.displayName,
          abbreviation: home.team.abbreviation,
          logo: home.team.logo,
          score: Number(home.score),
          record: home.records?.[0]?.summary
        },

        awayTeam: {
          id: away.team.id,
          name: away.team.displayName,
          abbreviation: away.team.abbreviation,
          logo: away.team.logo,
          score: Number(away.score),
          record: away.records?.[0]?.summary
        },

        // ⏱ period
        period: {
          current: event.status.period,
          type: event.status.type.name === "STATUS_OVERTIME" ? "OT" : "REG",
          isHalftime: event.status.type.description === "Halftime"
        },

        // 📺 broadcast
        broadcasts: event.competitions[0].broadcasts?.map(b => ({
          market: b.market,
          network: b.names?.[0]
        })),

        // 🔗 links
        gameLink: event.links?.[0]?.href,

        // 🎥 STREAM (your injection)
        stream: streamData?.stream || null,
        channel: streamData?.channel || null,
        streamProvider: streamData?.streamProvider || null
      };
    });

    cache = games;
    cacheTime = Date.now();

    res.status(200).json(games);

  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "failed" });
  }
}