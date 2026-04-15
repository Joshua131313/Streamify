
// const nbaStreams = [
//   "https://topstreams.info/iframe/nba/lakers",
//   "https://v2.trendy47.com/event/ppv-team1id-vs-team2-id"
// ]

import type { SportStream, TeamInfo } from "../../types/sports/sportsTypes";
import { createViewEmbedStreams, getSlug } from "./sportsData";



export const nbaTeamsMap : Record<string, TeamInfo> = {
  ATL: { abbreviation: "ATL", teamName: "Atlanta Hawks", id: "atlanta-hawks", conference: "East", division: "Southeast", league: "NBA" },
  BOS: { abbreviation: "BOS", teamName: "Boston Celtics", id: "boston-celtics", conference: "East", division: "Atlantic", league: "NBA" },
  BKN: { abbreviation: "BKN", teamName: "Brooklyn Nets", id: "brooklyn-nets", conference: "East", division: "Atlantic", league: "NBA" },
  CHA: { abbreviation: "CHA", teamName: "Charlotte Hornets", id: "charlotte-hornets", conference: "East", division: "Southeast", league: "NBA" },
  CHI: { abbreviation: "CHI", teamName: "Chicago Bulls", id: "chicago-bulls", conference: "East", division: "Central", league: "NBA" },
  CLE: { abbreviation: "CLE", teamName: "Cleveland Cavaliers", id: "cleveland-cavaliers", conference: "East", division: "Central", league: "NBA" },
  DET: { abbreviation: "DET", teamName: "Detroit Pistons", id: "detroit-pistons", conference: "East", division: "Central", league: "NBA" },
  IND: { abbreviation: "IND", teamName: "Indiana Pacers", id: "indiana-pacers", conference: "East", division: "Central", league: "NBA" },
  MIA: { abbreviation: "MIA", teamName: "Miami Heat", id: "miami-heat", conference: "East", division: "Southeast", league: "NBA" },
  MIL: { abbreviation: "MIL", teamName: "Milwaukee Bucks", id: "milwaukee-bucks", conference: "East", division: "Central", league: "NBA" },
  NY: { abbreviation: "NY", teamName: "New York Knicks", id: "new-york-knicks", conference: "East", division: "Atlantic", league: "NBA" },
  ORL: { abbreviation: "ORL", teamName: "Orlando Magic", id: "orlando-magic", conference: "East", division: "Southeast", league: "NBA" },
  PHI: { abbreviation: "PHI", teamName: "Philadelphia 76ers", id: "philadelphia-76-ers", conference: "East", division: "Atlantic", league: "NBA" },
  TOR: { abbreviation: "TOR", teamName: "Toronto Raptors", id: "toronto-raptors", conference: "East", division: "Atlantic", league: "NBA" },
  WSH: { abbreviation: "WSH", teamName: "Washington Wizards", id: "washington-wizards", conference: "East", division: "Southeast", league: "NBA" },

  DAL: { abbreviation: "DAL", teamName: "Dallas Mavericks", id: "dallas-mavericks", conference: "West", division: "Southwest", league: "NBA" },
  DEN: { abbreviation: "DEN", teamName: "Denver Nuggets", id: "denver-nuggets", conference: "West", division: "Northwest", league: "NBA" },
  GS: { abbreviation: "GS", teamName: "Golden State Warriors", id: "golden-state-warriors", conference: "West", division: "Pacific", league: "NBA" },
  HOU: { abbreviation: "HOU", teamName: "Houston Rockets", id: "houston-rockets", conference: "West", division: "Southwest", league: "NBA" },
  LAC: { abbreviation: "LAC", teamName: "Los Angeles Clippers", id: "la-clippers", conference: "West", division: "Pacific", league: "NBA" },
  LAL: { abbreviation: "LAL", teamName: "Los Angeles Lakers", id: "los-angeles-lakers", conference: "West", division: "Pacific", league: "NBA" },
  MEM: { abbreviation: "MEM", teamName: "Memphis Grizzlies", id: "memphis-grizzlies", conference: "West", division: "Southwest", league: "NBA" },
  MIN: { abbreviation: "MIN", teamName: "Minnesota Timberwolves", id: "minnesota-timberwolves", conference: "West", division: "Northwest", league: "NBA" },
  NO: { abbreviation: "NO", teamName: "New Orleans Pelicans", id: "new-orleans-pelicans", conference: "West", division: "Southwest", league: "NBA" },
  OKC: { abbreviation: "OKC", teamName: "Oklahoma City Thunder", id: "oklahoma-city-thunder", conference: "West", division: "Northwest", league: "NBA" },
  PHX: { abbreviation: "PHX", teamName: "Phoenix Suns", id: "phoenix-suns", conference: "West", division: "Pacific", league: "NBA" },
  POR: { abbreviation: "POR", teamName: "Portland Trail Blazers", id: "portland-trail-blazers", conference: "West", division: "Northwest", league: "NBA" },
  SAC: { abbreviation: "SAC", teamName: "Sacramento Kings", id: "sacramento-kings", conference: "West", division: "Pacific", league: "NBA" },
  SA: { abbreviation: "SA", teamName: "San Antonio Spurs", id: "san-antonio-spurs", conference: "West", division: "Southwest", league: "NBA" },
  UTAH: { abbreviation: "UTAH", teamName: "Utah Jazz", id: "utah-jazz", conference: "West", division: "Northwest", league: "NBA" }
};

export const nbaStreams: SportStream[] = [
  {
    provider: "trendy47",
    buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
      const homeId = nbaTeamsMap[homeTeamAbbrev as keyof typeof nbaTeamsMap]?.id;
      const awayId = nbaTeamsMap[awayTeamAbbrev as keyof typeof nbaTeamsMap]?.id;
      return `https://v2.trendy47.com/event/ppv-${awayId}-vs-${homeId}`;
    },
  },
  {
    provider: "topstreams",
    buildStreamUrl: ({ homeTeamAbbrev }) => {
      if (homeTeamAbbrev in nbaTeamsMap) {
        const teamName = nbaTeamsMap[homeTeamAbbrev as keyof typeof nbaTeamsMap].teamName;
        const slug = getSlug(teamName).toLowerCase();

        return `https://topstreams.info/iframe/nba/${slug}`;
      }

      return "";
    }
  },
  ...createViewEmbedStreams(nbaTeamsMap),

]