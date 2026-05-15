import type { SportStream, TeamInfo } from "../../types/sports/sportsTypes";
import { createViewEmbedStreams } from "./sportsData";



export const mlbTeamsMap: Record<string, TeamInfo> = {
  BAL: { abbreviation: "BAL", teamName: "Baltimore Orioles", id: "baltimore-orioles", conference: "AL", division: "East", league: "MLB", color: "#DF4601" },
  BOS: { abbreviation: "BOS", teamName: "Boston Red Sox", id: "boston-red-sox", conference: "AL", division: "East", league: "MLB", color: "#BD3039" },
  NYY: { abbreviation: "NYY", teamName: "New York Yankees", id: "new-york-yankees", conference: "AL", division: "East", league: "MLB", color: "#003087" },
  TB: { abbreviation: "TB", teamName: "Tampa Bay Rays", id: "tampa-bay-rays", conference: "AL", division: "East", league: "MLB", color: "#092C5C" },
  TOR: { abbreviation: "TOR", teamName: "Toronto Blue Jays", id: "toronto-blue-jays", conference: "AL", division: "East", league: "MLB", color: "#134A8E" },

  CHW: { abbreviation: "CHW", teamName: "Chicago White Sox", id: "chicago-white-sox", conference: "AL", division: "Central", league: "MLB", color: "#000000" },
  CLE: { abbreviation: "CLE", teamName: "Cleveland Guardians", id: "cleveland-guardians", conference: "AL", division: "Central", league: "MLB", color: "#E50022" },
  DET: { abbreviation: "DET", teamName: "Detroit Tigers", id: "detroit-tigers", conference: "AL", division: "Central", league: "MLB", color: "#0C2340" },
  KC: { abbreviation: "KC", teamName: "Kansas City Royals", id: "kansas-city-royals", conference: "AL", division: "Central", league: "MLB", color: "#004687" },
  MIN: { abbreviation: "MIN", teamName: "Minnesota Twins", id: "minnesota-twins", conference: "AL", division: "Central", league: "MLB", color: "#002B5C" },

  HOU: { abbreviation: "HOU", teamName: "Houston Astros", id: "houston-astros", conference: "AL", division: "West", league: "MLB", color: "#EB6E1F" },
  LAA: { abbreviation: "LAA", teamName: "Los Angeles Angels", id: "los-angeles-angels", conference: "AL", division: "West", league: "MLB", color: "#BA0021" },
  ATH: { abbreviation: "ATH", teamName: "Athletics", id: "athletics", conference: "AL", division: "West", league: "MLB", color: "#003831" },
  SEA: { abbreviation: "SEA", teamName: "Seattle Mariners", id: "seattle-mariners", conference: "AL", division: "West", league: "MLB", color: "#005C5C" },
  TEX: { abbreviation: "TEX", teamName: "Texas Rangers", id: "texas-rangers", conference: "AL", division: "West", league: "MLB", color: "#003278" },

  ATL: { abbreviation: "ATL", teamName: "Atlanta Braves", id: "atlanta-braves", conference: "NL", division: "East", league: "MLB", color: "#CE1141" },
  MIA: { abbreviation: "MIA", teamName: "Miami Marlins", id: "miami-marlins", conference: "NL", division: "East", league: "MLB", color: "#00A3E0" },
  NYM: { abbreviation: "NYM", teamName: "New York Mets", id: "new-york-mets", conference: "NL", division: "East", league: "MLB", color: "#002D72" },
  PHI: { abbreviation: "PHI", teamName: "Philadelphia Phillies", id: "philadelphia-phillies", conference: "NL", division: "East", league: "MLB", color: "#E81828" },
  WSH: { abbreviation: "WSH", teamName: "Washington Nationals", id: "washington-nationals", conference: "NL", division: "East", league: "MLB", color: "#AB0003" },

  CHC: { abbreviation: "CHC", teamName: "Chicago Cubs", id: "chicago-cubs", conference: "NL", division: "Central", league: "MLB", color: "#0E3386" },
  CIN: { abbreviation: "CIN", teamName: "Cincinnati Reds", id: "cincinnati-reds", conference: "NL", division: "Central", league: "MLB", color: "#C6011F" },
  MIL: { abbreviation: "MIL", teamName: "Milwaukee Brewers", id: "milwaukee-brewers", conference: "NL", division: "Central", league: "MLB", color: "#FFC52F" },
  PIT: { abbreviation: "PIT", teamName: "Pittsburgh Pirates", id: "pittsburgh-pirates", conference: "NL", division: "Central", league: "MLB", color: "#FDB827" },
  STL: { abbreviation: "STL", teamName: "St. Louis Cardinals", id: "st-louis-cardinals", conference: "NL", division: "Central", league: "MLB", color: "#C41E3A" },

  ARI: { abbreviation: "ARI", teamName: "Arizona Diamondbacks", id: "arizona-diamondbacks", conference: "NL", division: "West", league: "MLB", color: "#A6192E" },
  COL: { abbreviation: "COL", teamName: "Colorado Rockies", id: "colorado-rockies", conference: "NL", division: "West", league: "MLB", color: "#33006F" },
  LAD: { abbreviation: "LAD", teamName: "Los Angeles Dodgers", id: "los-angeles-dodgers", conference: "NL", division: "West", league: "MLB", color: "#005A9C" },
  SD: { abbreviation: "SD", teamName: "San Diego Padres", id: "san-diego-padres", conference: "NL", division: "West", league: "MLB", color: "#2F241D" },
  SF: { abbreviation: "SF", teamName: "San Francisco Giants", id: "san-francisco-giants", conference: "NL", division: "West", league: "MLB", color: "#FD5A1E" }
};

export const mlbStreams: SportStream[] = [
    // {
    //     provider: "streamspass",
    //     buildStreamUrl: ({awayTeamAbbrev, homeTeamAbbrev}) => {
    //         const teamName = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap].teamName;
    //         const slug = getSlug(teamName).toLowerCase();
    //         return `https://streamspass.net/mlb/${slug}.html`
    //     }
    // },
    {
        provider: "embedsports-top",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
            const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

            if (!home || !away) return "";
            return `https://embedsports.top/embed/admin/ppv-${away.id}-vs-${home.id}/1#player=clappr`
        }
    },


    // {
    //     provider: "embedsports-d",
    //     buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
    //         const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
    //         const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

    //         if (!home || !away) return "";
    //         const homeSlug = getSlug(home.teamName).toLowerCase();
    //         const awaySlug = getSlug(away.teamName).toLowerCase();
    //         return `https://embedsports.top/embed/delta/live_mlb_${homeSlug}-${awaySlug}-live-streaming-1197515286/1#player=clappr`
    //     }
    // },
    {
        provider: "pooembed",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
            const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

            if (!home || !away) return "";

            const homeAbbrev = home.abbreviation.toLowerCase();
            const awayAbbrev = away.abbreviation.toLowerCase();

            const now = new Date();
            const adjustedDate = new Date(now);

            // If it's between 12:00 AM and 5:59 AM, use the previous day
            if (now.getHours() < 6) {
                adjustedDate.setDate(adjustedDate.getDate() - 1);
            }

            const gameDay = adjustedDate.toLocaleDateString("en-CA");

            return `https://pooembed.eu/embed/mlb/${gameDay}/${awayAbbrev}-${homeAbbrev}#autoplay=true`;
        }
    },
    {
        provider: "embedsports-home",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const id = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap].id;
            return `https://embedsports.me/mlb/${id}-stream-1`
        },
        label: "Home 1"
    },
    {
        provider: "embedsports-away",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const id = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap].id;
            return `https://embedsports.me/mlb/${id}-stream-1`
        },
        label: "Away 1"
    },
    ...createViewEmbedStreams(mlbTeamsMap),

];