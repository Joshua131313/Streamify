import type { SportStream, TeamInfo } from "../../types/sports/sportsTypes";
import { createViewEmbedStreams, getSlug } from "./sportsData";



export const mlbTeamsMap : Record<string, TeamInfo> = {
    // AL EAST
    BAL: {
        abbreviation: "BAL",
        teamName: "Baltimore Orioles",
        id: "baltimore-orioles",
        conference: "AL",
        division: "East",
        league: "MLB"
    },
    BOS: {
        abbreviation: "BOS",
        teamName: "Boston Red Sox",
        id: "boston-red-sox",
        conference: "AL",
        division: "East",
        league: "MLB"
    },
    NYY: {
        abbreviation: "NYY",
        teamName: "New York Yankees",
        id: "new-york-yankees",
        conference: "AL",
        division: "East",
        league: "MLB"
    },
    TB: {
        abbreviation: "TB",
        teamName: "Tampa Bay Rays",
        id: "tampa-bay-rays",
        conference: "AL",
        division: "East",
        league: "MLB"
    },
    TOR: {
        abbreviation: "TOR",
        teamName: "Toronto Blue Jays",
        id: "toronto-blue-jays",
        conference: "AL",
        division: "East",
        league: "MLB"
    },

    // AL CENTRAL
    CHW: {
        abbreviation: "CHW",
        teamName: "Chicago White Sox",
        id: "chicago-white-sox",
        conference: "AL",
        division: "Central",
        league: "MLB"
    },
    CLE: {
        abbreviation: "CLE",
        teamName: "Cleveland Guardians",
        id: "cleveland-guardians",
        conference: "AL",
        division: "Central",
        league: "MLB"
    },
    DET: {
        abbreviation: "DET",
        teamName: "Detroit Tigers",
        id: "detroit-tigers",
        conference: "AL",
        division: "Central",
        league: "MLB"
    },
    KC: {
        abbreviation: "KC",
        teamName: "Kansas City Royals",
        id: "kansas-city-royals",
        conference: "AL",
        division: "Central",
        league: "MLB"
    },
    MIN: {
        abbreviation: "MIN",
        teamName: "Minnesota Twins",
        id: "minnesota-twins",
        conference: "AL",
        division: "Central",
        league: "MLB"
    },

    // AL WEST
    HOU: {
        abbreviation: "HOU",
        teamName: "Houston Astros",
        id: "houston-astros",
        conference: "AL",
        division: "West",
        league: "MLB"
    },
    LAA: {
        abbreviation: "LAA",
        teamName: "Los Angeles Angels",
        id: "los-angeles-angels",
        conference: "AL",
        division: "West",
        league: "MLB"
    },
    ATH: {
        abbreviation: "ATH",
        teamName: "Athletics",
        id: "athletics",
        conference: "AL",
        division: "West",
        league: "MLB"
    },
    SEA: {
        abbreviation: "SEA",
        teamName: "Seattle Mariners",
        id: "seattle-mariners",
        conference: "AL",
        division: "West",
        league: "MLB"
    },
    TEX: {
        abbreviation: "TEX",
        teamName: "Texas Rangers",
        id: "texas-rangers",
        conference: "AL",
        division: "West",
        league: "MLB"
    },

    // NL EAST
    ATL: {
        abbreviation: "ATL",
        teamName: "Atlanta Braves",
        id: "atlanta-braves",
        conference: "NL",
        division: "East",
        league: "MLB"
    },
    MIA: {
        abbreviation: "MIA",
        teamName: "Miami Marlins",
        id: "miami-marlins",
        conference: "NL",
        division: "East",
        league: "MLB"
    },
    NYM: {
        abbreviation: "NYM",
        teamName: "New York Mets",
        id: "new-york-mets",
        conference: "NL",
        division: "East",
        league: "MLB"
    },
    PHI: {
        abbreviation: "PHI",
        teamName: "Philadelphia Phillies",
        id: "philadelphia-phillies",
        conference: "NL",
        division: "East",
        league: "MLB"
    },
    WSH: {
        abbreviation: "WSH",
        teamName: "Washington Nationals",
        id: "washington-nationals",
        conference: "NL",
        division: "East",
        league: "MLB"
    },

    // NL CENTRAL
    CHC: {
        abbreviation: "CHC",
        teamName: "Chicago Cubs",
        id: "chicago-cubs",
        conference: "NL",
        division: "Central",
        league: "MLB"
    },
    CIN: {
        abbreviation: "CIN",
        teamName: "Cincinnati Reds",
        id: "cincinnati-reds",
        conference: "NL",
        division: "Central",
        league: "MLB"
    },
    MIL: {
        abbreviation: "MIL",
        teamName: "Milwaukee Brewers",
        id: "milwaukee-brewers",
        conference: "NL",
        division: "Central",
        league: "MLB"
    },
    PIT: {
        abbreviation: "PIT",
        teamName: "Pittsburgh Pirates",
        id: "pittsburgh-pirates",
        conference: "NL",
        division: "Central",
        league: "MLB"
    },
    STL: {
        abbreviation: "STL",
        teamName: "St. Louis Cardinals",
        id: "st-louis-cardinals", // 🔥 important fix
        conference: "NL",
        division: "Central",
        league: "MLB"
    },

    // NL WEST
    ARI: {
        abbreviation: "ARI",
        teamName: "Arizona Diamondbacks",
        id: "arizona-diamondbacks",
        conference: "NL",
        division: "West",
        league: "MLB"
    },
    COL: {
        abbreviation: "COL",
        teamName: "Colorado Rockies",
        id: "colorado-rockies",
        conference: "NL",
        division: "West",
        league: "MLB"
    },
    LAD: {
        abbreviation: "LAD",
        teamName: "Los Angeles Dodgers",
        id: "los-angeles-dodgers",
        conference: "NL",
        division: "West",
        league: "MLB"
    },
    SD: {
        abbreviation: "SD",
        teamName: "San Diego Padres",
        id: "san-diego-padres",
        conference: "NL",
        division: "West",
        league: "MLB"
    },
    SF: {
        abbreviation: "SF",
        teamName: "San Francisco Giants",
        id: "san-francisco-giants",
        conference: "NL",
        division: "West",
        league: "MLB"
    }
};

export const mlbStreams: SportStream[] = [
    {
        provider: "embedsports",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
            const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

            if (!home || !away) return "";
            return `https://embedsports.top/embed/admin/ppv-${away.id}-vs-${home.id}/1#player=clappr`
        }
    },
    {
        provider: "embedsports-d",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
            const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

            if (!home || !away) return "";
            const homeSlug = getSlug(home.teamName).toLowerCase();
            const awaySlug = getSlug(away.teamName).toLowerCase();
            return `https://embedsports.top/embed/delta/live_mlb_${homeSlug}-${awaySlug}-live-streaming-1197515286/1#player=clappr`
        }
    },
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
    ...createViewEmbedStreams(mlbTeamsMap),

];