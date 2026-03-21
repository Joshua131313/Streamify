import axios from "axios";
import * as cheerio from "cheerio";

const ONE_DAY = 24 * 60 * 60 * 1000;

let cache = null;
let cacheTime = 0;

const NBA_TEAM_IDS = {
  "Atlanta Hawks": "1610612737",
  "Boston Celtics": "1610612738",
  "Brooklyn Nets": "1610612751",
  "Charlotte Hornets": "1610612766",
  "Chicago Bulls": "1610612741",
  "Cleveland Cavaliers": "1610612739",
  "Dallas Mavericks": "1610612742",
  "Denver Nuggets": "1610612743",
  "Detroit Pistons": "1610612765",
  "Golden State Warriors": "1610612744",
  "Houston Rockets": "1610612745",
  "Indiana Pacers": "1610612754",
  "Los Angeles Clippers": "1610612746",
  "Los Angeles Lakers": "1610612747",
  "Memphis Grizzlies": "1610612763",
  "Miami Heat": "1610612748",
  "Milwaukee Bucks": "1610612749",
  "Minnesota Timberwolves": "1610612750",
  "New Orleans Pelicans": "1610612740",
  "New York Knicks": "1610612752",
  "Oklahoma City Thunder": "1610612760",
  "Orlando Magic": "1610612753",
  "Philadelphia 76ers": "1610612755",
  "Phoenix Suns": "1610612756",
  "Portland Trail Blazers": "1610612757",
  "Sacramento Kings": "1610612758",
  "San Antonio Spurs": "1610612759",
  "Toronto Raptors": "1610612761",
  "Utah Jazz": "1610612762",
  "Washington Wizards": "1610612764"
};

function getLogo(team) {
  const id = NBA_TEAM_IDS[team];
  if (!id) return null;

  return `https://cdn.nba.com/logos/nba/${id}/global/L/logo.svg`;
}

export default async function handler(req, res) {
  try {
    // ✅ cache
    if (cache && Date.now() - cacheTime < ONE_DAY) {
      return res.status(200).json(cache);
    }

    const response = await axios.get(
      "https://sharkstreams.net/category/nba",
      {
        headers: {
          "User-Agent": "Mozilla/5.0"
        }
      }
    );

    const $ = cheerio.load(response.data);

    const games = [];

    $(".row").each((i, el) => {
      const dateRaw = $(el).find(".ch-date").text().trim();
      const game = $(el).find(".ch-name").text().trim();
      const watch = $(el).find(".hd-link").first().attr("onclick");

      const isoDate = dateRaw.replace(" ", "T")


      // ✅ simple logic
      let stream = null;

      if (watch) {
        const match = watch.match(/'(https:\/\/[^']+)'/);
        if (match) stream = match[1];
      }

      if (game) {
        const [homeTeam, awayTeam] = game.split(" vs ");

        games.push({
          date: isoDate,
          game,
          stream,
          homeTeam: {
            name: homeTeam,
            logo: getLogo(homeTeam)
          },
          awayTeam: {
            name: awayTeam,
            logo: getLogo(awayTeam)
          }
        });
      }
    });

    cache = games;
    cacheTime = Date.now();

    return res.status(200).json(games);

  } catch (err) {
    console.error("SCRAPE ERROR:", err);
    return res.status(500).json({ error: "scrape failed" });
  }
}