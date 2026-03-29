import type { SportStream } from "../../types/sports/sportsTypes";
import { getSlug } from "./sportsData";

export const mlbStreams: SportStream[] = [
    {
        provider: "embedsports",

        buildChannel: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
            const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

            if (!home || !away) return "";


            return `${away.id}-vs-${home.id}`;
        },

        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
            const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

            if (!home || !away) return "";
            return `https://embedsports.top/embed/admin/ppv-${away.id}-vs-${home.id}/1#player=clappr`
        }
    },
    {
        provider: "embedsports-d",

        buildChannel: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
            const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

            if (!home || !away) return "";
            const homeSlug = getSlug(home.teamName);
            const awaySlug = getSlug(away.teamName);

            return `${homeSlug}-${awaySlug}`;
        },

        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
            const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

            if (!home || !away) return "";
            const homeSlug = getSlug(home.teamName);
            const awaySlug = getSlug(away.teamName);
            return `https://embedsports.top/embed/delta/live_mlb_${homeSlug}-${awaySlug}-live-streaming-1197515286/1#player=clappr`
        }
    },
    {
        provider: "pooembed",

        buildChannel: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
            const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

            if (!home || !away) return "";
            const homeAbbrev = home.abbreviation.toLowerCase();
            const awayAbbrev = away.abbreviation.toLowerCase();

            return `${awayAbbrev}-${homeAbbrev}`;
        },

        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const home = mlbTeamsMap[homeTeamAbbrev as keyof typeof mlbTeamsMap];
            const away = mlbTeamsMap[awayTeamAbbrev as keyof typeof mlbTeamsMap];

            if (!home || !away) return "";
            const homeAbbrev = home.abbreviation.toLowerCase();
            const awayAbbrev = away.abbreviation.toLowerCase();
            return `https://pooembed.eu/embed/mlb/2026-03-27/${awayAbbrev}-${homeAbbrev}#autoplay=true`
        }
    },
];

export const mlbTeamsMap = {
    // AL EAST
    BAL: {
        abbreviation: "BAL",
        teamName: "Baltimore Orioles",
        id: "baltimore-orioles",
        logo: "https://www.mlbstatic.com/team-logos/110.svg",
        league: "AL",
        division: "East"
    },
    BOS: {
        abbreviation: "BOS",
        teamName: "Boston Red Sox",
        id: "boston-red-sox",
        logo: "https://www.mlbstatic.com/team-logos/111.svg",
        league: "AL",
        division: "East"
    },
    NYY: {
        abbreviation: "NYY",
        teamName: "New York Yankees",
        id: "new-york-yankees",
        logo: "https://www.mlbstatic.com/team-logos/147.svg",
        league: "AL",
        division: "East"
    },
    TB: {
        abbreviation: "TB",
        teamName: "Tampa Bay Rays",
        id: "tampa-bay-rays",
        logo: "https://www.mlbstatic.com/team-logos/139.svg",
        league: "AL",
        division: "East"
    },
    TOR: {
        abbreviation: "TOR",
        teamName: "Toronto Blue Jays",
        id: "toronto-blue-jays",
        logo: "https://www.mlbstatic.com/team-logos/141.svg",
        league: "AL",
        division: "East"
    },

    // AL CENTRAL
    CHW: {
        abbreviation: "CHW",
        teamName: "Chicago White Sox",
        id: "chicago-white-sox",
        logo: "https://www.mlbstatic.com/team-logos/145.svg",
        league: "AL",
        division: "Central"
    },
    CLE: {
        abbreviation: "CLE",
        teamName: "Cleveland Guardians",
        id: "cleveland-guardians",
        logo: "https://www.mlbstatic.com/team-logos/114.svg",
        league: "AL",
        division: "Central"
    },
    DET: {
        abbreviation: "DET",
        teamName: "Detroit Tigers",
        id: "detroit-tigers",
        logo: "https://www.mlbstatic.com/team-logos/116.svg",
        league: "AL",
        division: "Central"
    },
    KC: {
        abbreviation: "KC",
        teamName: "Kansas City Royals",
        id: "kansas-city-royals",
        logo: "https://www.mlbstatic.com/team-logos/118.svg",
        league: "AL",
        division: "Central"
    },
    MIN: {
        abbreviation: "MIN",
        teamName: "Minnesota Twins",
        id: "minnesota-twins",
        logo: "https://www.mlbstatic.com/team-logos/142.svg",
        league: "AL",
        division: "Central"
    },

    // AL WEST
    HOU: {
        abbreviation: "HOU",
        teamName: "Houston Astros",
        id: "houston-astros",
        logo: "https://www.mlbstatic.com/team-logos/117.svg",
        league: "AL",
        division: "West"
    },
    LAA: {
        abbreviation: "LAA",
        teamName: "Los Angeles Angels",
        id: "los-angeles-angels",
        logo: "https://www.mlbstatic.com/team-logos/108.svg",
        league: "AL",
        division: "West"
    },
    ATH: {
        abbreviation: "ATH",
        teamName: "Athletics",
        id: "athletics",
        logo: "https://www.mlbstatic.com/team-logos/133.svg",
        league: "AL",
        division: "West"
    },
    SEA: {
        abbreviation: "SEA",
        teamName: "Seattle Mariners",
        id: "seattle-mariners",
        logo: "https://www.mlbstatic.com/team-logos/136.svg",
        league: "AL",
        division: "West"
    },
    TEX: {
        abbreviation: "TEX",
        teamName: "Texas Rangers",
        id: "texas-rangers",
        logo: "https://www.mlbstatic.com/team-logos/140.svg",
        league: "AL",
        division: "West"
    },

    // NL EAST
    ATL: {
        abbreviation: "ATL",
        teamName: "Atlanta Braves",
        id: "atlanta-braves",
        logo: "https://www.mlbstatic.com/team-logos/144.svg",
        league: "NL",
        division: "East"
    },
    MIA: {
        abbreviation: "MIA",
        teamName: "Miami Marlins",
        id: "miami-marlins",
        logo: "https://www.mlbstatic.com/team-logos/146.svg",
        league: "NL",
        division: "East"
    },
    NYM: {
        abbreviation: "NYM",
        teamName: "New York Mets",
        id: "new-york-mets",
        logo: "https://www.mlbstatic.com/team-logos/121.svg",
        league: "NL",
        division: "East"
    },
    PHI: {
        abbreviation: "PHI",
        teamName: "Philadelphia Phillies",
        id: "philadelphia-phillies",
        logo: "https://www.mlbstatic.com/team-logos/143.svg",
        league: "NL",
        division: "East"
    },
    WSH: {
        abbreviation: "WSH",
        teamName: "Washington Nationals",
        id: "washington-nationals",
        logo: "https://www.mlbstatic.com/team-logos/120.svg",
        league: "NL",
        division: "East"
    },

    // NL CENTRAL
    CHC: {
        abbreviation: "CHC",
        teamName: "Chicago Cubs",
        id: "chicago-cubs",
        logo: "https://www.mlbstatic.com/team-logos/112.svg",
        league: "NL",
        division: "Central"
    },
    CIN: {
        abbreviation: "CIN",
        teamName: "Cincinnati Reds",
        id: "cincinnati-reds",
        logo: "https://www.mlbstatic.com/team-logos/113.svg",
        league: "NL",
        division: "Central"
    },
    MIL: {
        abbreviation: "MIL",
        teamName: "Milwaukee Brewers",
        id: "milwaukee-brewers",
        logo: "https://www.mlbstatic.com/team-logos/158.svg",
        league: "NL",
        division: "Central"
    },
    PIT: {
        abbreviation: "PIT",
        teamName: "Pittsburgh Pirates",
        id: "pittsburgh-pirates",
        logo: "https://www.mlbstatic.com/team-logos/134.svg",
        league: "NL",
        division: "Central"
    },
    STL: {
        abbreviation: "STL",
        teamName: "St. Louis Cardinals",
        id: "st-louis-cardinals", // 🔥 important fix
        logo: "https://www.mlbstatic.com/team-logos/138.svg",
        league: "NL",
        division: "Central"
    },

    // NL WEST
    ARI: {
        abbreviation: "ARI",
        teamName: "Arizona Diamondbacks",
        id: "arizona-diamondbacks",
        logo: "https://www.mlbstatic.com/team-logos/109.svg",
        league: "NL",
        division: "West"
    },
    COL: {
        abbreviation: "COL",
        teamName: "Colorado Rockies",
        id: "colorado-rockies",
        logo: "https://www.mlbstatic.com/team-logos/115.svg",
        league: "NL",
        division: "West"
    },
    LAD: {
        abbreviation: "LAD",
        teamName: "Los Angeles Dodgers",
        id: "los-angeles-dodgers",
        logo: "https://www.mlbstatic.com/team-logos/119.svg",
        league: "NL",
        division: "West"
    },
    SD: {
        abbreviation: "SD",
        teamName: "San Diego Padres",
        id: "san-diego-padres",
        logo: "https://www.mlbstatic.com/team-logos/135.svg",
        league: "NL",
        division: "West"
    },
    SF: {
        abbreviation: "SF",
        teamName: "San Francisco Giants",
        id: "san-francisco-giants",
        logo: "https://www.mlbstatic.com/team-logos/137.svg",
        league: "NL",
        division: "West"
    }
};