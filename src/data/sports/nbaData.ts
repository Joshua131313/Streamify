
// const nbaStreams = [
//   "https://topstreams.info/iframe/nba/lakers",
//   "https://v2.trendy47.com/event/ppv-team1id-vs-team2-id"
// ]

import type { SportStream } from "../../types/sports/sportsTypes";

export const nbaStreams: SportStream[] = [
  {
    provider: "trendy47",
    buildChannel: (game) => {
      const homeId = nbaTeamsMap[game.homeTeam.abbrev as keyof typeof nbaTeamsMap]?.id;
      const awayId = nbaTeamsMap[game.awayTeam.abbrev as keyof typeof nbaTeamsMap]?.id;
      return `${awayId}-vs-${homeId}`
    },
    buildStreamUrl: (game) => {
      const homeId = nbaTeamsMap[game.homeTeam.abbrev as keyof typeof nbaTeamsMap]?.id;
      const awayId = nbaTeamsMap[game.awayTeam.abbrev as keyof typeof nbaTeamsMap]?.id;
      return `https://v2.trendy47.com/event/ppv-${awayId}-vs-${homeId}`;
    }
  },
  {
    provider: "topstreams",
    buildChannel: (game) => {
      const parts = game.homeTeam.name.split(" ");
      const teamSlug = parts[parts.length - 1].toLowerCase();
      return teamSlug
    },
    buildStreamUrl: (game) => {
      const parts = game.homeTeam.name.split(" ");
      const teamSlug = parts[parts.length - 1].toLowerCase();

      return `https://topstreams.info/iframe/nba/${teamSlug}`;
    }
  }
]

export const nbaTeamsMap = {
  ATL: { abbreviation: "ATL", teamName: "Atlanta Hawks", id: "atlanta-hawks", logo: "https://cdn.nba.com/logos/nba/1610612737/global/L/logo.svg", conference: "East", division: "Southeast" },
  BOS: { abbreviation: "BOS", teamName: "Boston Celtics", id: "boston-celtics", logo: "https://cdn.nba.com/logos/nba/1610612738/global/L/logo.svg", conference: "East", division: "Atlantic" },
  BKN: { abbreviation: "BKN", teamName: "Brooklyn Nets", id: "brooklyn-nets", logo: "https://cdn.nba.com/logos/nba/1610612751/global/L/logo.svg", conference: "East", division: "Atlantic" },
  CHA: { abbreviation: "CHA", teamName: "Charlotte Hornets", id: "charlotte-hornets", logo: "https://cdn.nba.com/logos/nba/1610612766/global/L/logo.svg", conference: "East", division: "Southeast" },
  CHI: { abbreviation: "CHI", teamName: "Chicago Bulls", id: "chicago-bulls", logo: "https://cdn.nba.com/logos/nba/1610612741/global/L/logo.svg", conference: "East", division: "Central" },
  CLE: { abbreviation: "CLE", teamName: "Cleveland Cavaliers", id: "cleveland-cavaliers", logo: "https://cdn.nba.com/logos/nba/1610612739/global/L/logo.svg", conference: "East", division: "Central" },
  DET: { abbreviation: "DET", teamName: "Detroit Pistons", id: "detroit-pistons", logo: "https://cdn.nba.com/logos/nba/1610612765/global/L/logo.svg", conference: "East", division: "Central" },
  IND: { abbreviation: "IND", teamName: "Indiana Pacers", id: "indiana-pacers", logo: "https://cdn.nba.com/logos/nba/1610612754/global/L/logo.svg", conference: "East", division: "Central" },
  MIA: { abbreviation: "MIA", teamName: "Miami Heat", id: "miami-heat", logo: "https://cdn.nba.com/logos/nba/1610612748/global/L/logo.svg", conference: "East", division: "Southeast" },
  MIL: { abbreviation: "MIL", teamName: "Milwaukee Bucks", id: "milwaukee-bucks", logo: "https://cdn.nba.com/logos/nba/1610612749/global/L/logo.svg", conference: "East", division: "Central" },
  NY: { abbreviation: "NYK", teamName: "New York Knicks", id: "new-york-knicks", logo: "https://cdn.nba.com/logos/nba/1610612752/global/L/logo.svg", conference: "East", division: "Atlantic" },
  ORL: { abbreviation: "ORL", teamName: "Orlando Magic", id: "orlando-magic", logo: "https://cdn.nba.com/logos/nba/1610612753/global/L/logo.svg", conference: "East", division: "Southeast" },
  PHI: { abbreviation: "PHI", teamName: "Philadelphia 76ers", id: "philadelphia-76ers", logo: "https://cdn.nba.com/logos/nba/1610612755/global/L/logo.svg", conference: "East", division: "Atlantic" },
  TOR: { abbreviation: "TOR", teamName: "Toronto Raptors", id: "toronto-raptors", logo: "https://cdn.nba.com/logos/nba/1610612761/global/L/logo.svg", conference: "East", division: "Atlantic" },
  WAS: { abbreviation: "WAS", teamName: "Washington Wizards", id: "washington-wizards", logo: "https://cdn.nba.com/logos/nba/1610612764/global/L/logo.svg", conference: "East", division: "Southeast" },

  DAL: { abbreviation: "DAL", teamName: "Dallas Mavericks", id: "dallas-mavericks", logo: "https://cdn.nba.com/logos/nba/1610612742/global/L/logo.svg", conference: "West", division: "Southwest" },
  DEN: { abbreviation: "DEN", teamName: "Denver Nuggets", id: "denver-nuggets", logo: "https://cdn.nba.com/logos/nba/1610612743/global/L/logo.svg", conference: "West", division: "Northwest" },
  GS: { abbreviation: "GS", teamName: "Golden State Warriors", id: "golden-state-warriors", logo: "https://cdn.nba.com/logos/nba/1610612744/global/L/logo.svg", conference: "West", division: "Pacific" },
  HOU: { abbreviation: "HOU", teamName: "Houston Rockets", id: "houston-rockets", logo: "https://cdn.nba.com/logos/nba/1610612745/global/L/logo.svg", conference: "West", division: "Southwest" },
  LAC: { abbreviation: "LAC", teamName: "Los Angeles Clippers", id: "la-clippers", logo: "https://cdn.nba.com/logos/nba/1610612746/global/L/logo.svg", conference: "West", division: "Pacific" },
  LAL: { abbreviation: "LAL", teamName: "Los Angeles Lakers", id: "los-angeles-lakers", logo: "https://cdn.nba.com/logos/nba/1610612747/global/L/logo.svg", conference: "West", division: "Pacific" },
  MEM: { abbreviation: "MEM", teamName: "Memphis Grizzlies", id: "memphis-grizzlies", logo: "https://cdn.nba.com/logos/nba/1610612763/global/L/logo.svg", conference: "West", division: "Southwest" },
  MIN: { abbreviation: "MIN", teamName: "Minnesota Timberwolves", id: "minnesota-timberwolves", logo: "https://cdn.nba.com/logos/nba/1610612750/global/L/logo.svg", conference: "West", division: "Northwest" },
  NO: { abbreviation: "NOP", teamName: "New Orleans Pelicans", id: "new-orleans-pelicans", logo: "https://cdn.nba.com/logos/nba/1610612740/global/L/logo.svg", conference: "West", division: "Southwest" },
  OKC: { abbreviation: "OKC", teamName: "Oklahoma City Thunder", id: "oklahoma-city-thunder", logo: "https://cdn.nba.com/logos/nba/1610612760/global/L/logo.svg", conference: "West", division: "Northwest" },
  PHX: { abbreviation: "PHX", teamName: "Phoenix Suns", id: "phoenix-suns", logo: "https://cdn.nba.com/logos/nba/1610612756/global/L/logo.svg", conference: "West", division: "Pacific" },
  POR: { abbreviation: "POR", teamName: "Portland Trail Blazers", id: "portland-trail-blazers", logo: "https://cdn.nba.com/logos/nba/1610612757/global/L/logo.svg", conference: "West", division: "Northwest" },
  SAC: { abbreviation: "SAC", teamName: "Sacramento Kings", id: "sacramento-kings", logo: "https://cdn.nba.com/logos/nba/1610612758/global/L/logo.svg", conference: "West", division: "Pacific" },
  SA: { abbreviation: "SA", teamName: "San Antonio Spurs", id: "san-antonio-spurs", logo: "https://cdn.nba.com/logos/nba/1610612759/global/L/logo.svg", conference: "West", division: "Southwest" },
  UTAH: { abbreviation: "UTAH", teamName: "Utah Jazz", id: "utah-jazz", logo: "https://cdn.nba.com/logos/nba/1610612762/global/L/logo.svg", conference: "West", division: "Northwest" }
};