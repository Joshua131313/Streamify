import type { SportStream, TeamInfo } from "../../types/sports/sportsTypes";
import { getSlug } from "./sportsData";


export const nhlTeamsMap: Record<string, TeamInfo> = {
    ANA: {
        abbreviation: "ANA",
        teamName: "Anaheim Ducks",
        id: "anaheim-ducks",
        conference: "West",
        division: "Pacific",
        league: "NHL",
        color: "#F47A38"
    },
    UTA: {
        abbreviation: "UTA",
        teamName: "Utah Mammoth",
        id: "utah-mammoth",
        conference: "West",
        division: "Central",
        league: "NHL",
        color: "#71AFE5"
    },
    BOS: {
        abbreviation: "BOS",
        teamName: "Boston Bruins",
        id: "boston-bruins",
        conference: "East",
        division: "Atlantic",
        league: "NHL",
        color: "#FFB81C"
    },
    BUF: {
        abbreviation: "BUF",
        teamName: "Buffalo Sabres",
        id: "buffalo-sabres",
        conference: "East",
        division: "Atlantic",
        league: "NHL",
        color: "#003087"
    },
    CGY: {
        abbreviation: "CGY",
        teamName: "Calgary Flames",
        id: "calgary-flames",
        conference: "West",
        division: "Pacific",
        league: "NHL",
        color: "#C8102E"
    },
    CAR: {
        abbreviation: "CAR",
        teamName: "Carolina Hurricanes",
        id: "carolina-hurricanes",
        conference: "East",
        division: "Metropolitan",
        league: "NHL",
        color: "#CC0000"
    },
    CHI: {
        abbreviation: "CHI",
        teamName: "Chicago Blackhawks",
        id: "chicago-blackhawks",
        conference: "West",
        division: "Central",
        league: "NHL",
        color: "#CF0A2C"
    },
    COL: {
        abbreviation: "COL",
        teamName: "Colorado Avalanche",
        id: "colorado-avalanche",
        conference: "West",
        division: "Central",
        league: "NHL",
        color: "#6F263D"
    },
    CBJ: {
        abbreviation: "CBJ",
        teamName: "Columbus Blue Jackets",
        id: "columbus-blue-jackets",
        conference: "East",
        division: "Metropolitan",
        league: "NHL",
        color: "#002654"
    },
    DAL: {
        abbreviation: "DAL",
        teamName: "Dallas Stars",
        id: "dallas-stars",
        conference: "West",
        division: "Central",
        league: "NHL",
        color: "#006847"
    },
    DET: {
        abbreviation: "DET",
        teamName: "Detroit Red Wings",
        id: "detroit-red-wings",
        conference: "East",
        division: "Atlantic",
        league: "NHL",
        color: "#CE1126"
    },
    EDM: {
        abbreviation: "EDM",
        teamName: "Edmonton Oilers",
        id: "edmonton-oilers",
        conference: "West",
        division: "Pacific",
        league: "NHL",
        color: "#041E42"
    },
    FLA: {
        abbreviation: "FLA",
        teamName: "Florida Panthers",
        id: "florida-panthers",
        conference: "East",
        division: "Atlantic",
        league: "NHL",
        color: "#C8102E"
    },
    LA: {
        abbreviation: "LA",
        teamName: "Los Angeles Kings",
        id: "los-angeles-kings",
        conference: "West",
        division: "Pacific",
        league: "NHL",
        color: "#111111"
    },
    MIN: {
        abbreviation: "MIN",
        teamName: "Minnesota Wild",
        id: "minnesota-wild",
        conference: "West",
        division: "Central",
        league: "NHL",
        color: "#154734"
    },
    MTL: {
        abbreviation: "MTL",
        teamName: "Montreal Canadiens",
        id: "montreal-canadiens",
        conference: "East",
        division: "Atlantic",
        league: "NHL",
        color: "#AF1E2D"
    },
    NSH: {
        abbreviation: "NSH",
        teamName: "Nashville Predators",
        id: "nashville-predators",
        conference: "West",
        division: "Central",
        league: "NHL",
        color: "#FFB81C"
    },
    NJ: {
        abbreviation: "NJ",
        teamName: "New Jersey Devils",
        id: "new-jersey-devils",
        conference: "East",
        division: "Metropolitan",
        league: "NHL",
        color: "#CE1126"
    },
    NYI: {
        abbreviation: "NYI",
        teamName: "New York Islanders",
        id: "new-york-islanders",
        conference: "East",
        division: "Metropolitan",
        league: "NHL",
        color: "#00539B"
    },
    NYR: {
        abbreviation: "NYR",
        teamName: "New York Rangers",
        id: "new-york-rangers",
        conference: "East",
        division: "Metropolitan",
        league: "NHL",
        color: "#0038A8"
    },
    OTT: {
        abbreviation: "OTT",
        teamName: "Ottawa Senators",
        id: "ottawa-senators",
        conference: "East",
        division: "Atlantic",
        league: "NHL",
        color: "#C52032"
    },
    PHI: {
        abbreviation: "PHI",
        teamName: "Philadelphia Flyers",
        id: "philadelphia-flyers",
        conference: "East",
        division: "Metropolitan",
        league: "NHL",
        color: "#F74902"
    },
    PIT: {
        abbreviation: "PIT",
        teamName: "Pittsburgh Penguins",
        id: "pittsburgh-penguins",
        conference: "East",
        division: "Metropolitan",
        league: "NHL",
        color: "#FCB514"
    },
    SJ: {
        abbreviation: "SJ",
        teamName: "San Jose Sharks",
        id: "san-jose-sharks",
        conference: "West",
        division: "Pacific",
        league: "NHL",
        color: "#006D75"
    },
    SEA: {
        abbreviation: "SEA",
        teamName: "Seattle Kraken",
        id: "seattle-kraken",
        conference: "West",
        division: "Pacific",
        league: "NHL",
        color: "#001628"
    },
    STL: {
        abbreviation: "STL",
        teamName: "St. Louis Blues",
        id: "st-louis-blues",
        conference: "West",
        division: "Central",
        league: "NHL",
        color: "#002F87"
    },
    TB: {
        abbreviation: "TB",
        teamName: "Tampa Bay Lightning",
        id: "tampa-bay-lightning",
        conference: "East",
        division: "Atlantic",
        league: "NHL",
        color: "#002868"
    },
    TOR: {
        abbreviation: "TOR",
        teamName: "Toronto Maple Leafs",
        id: "toronto-maple-leafs",
        conference: "East",
        division: "Atlantic",
        league: "NHL",
        color: "#00205B"
    },
    VAN: {
        abbreviation: "VAN",
        teamName: "Vancouver Canucks",
        id: "vancouver-canucks",
        conference: "West",
        division: "Pacific",
        league: "NHL",
        color: "#00205B"
    },
    VGK: {
        abbreviation: "VGK",
        teamName: "Vegas Golden Knights",
        id: "vegas-golden-knights",
        conference: "West",
        division: "Pacific",
        league: "NHL",
        color: "#B4975A"
    },
    WSH: {
        abbreviation: "WSH",
        teamName: "Washington Capitals",
        id: "washington-capitals",
        conference: "East",
        division: "Metropolitan",
        league: "NHL",
        color: "#041E42"
    },
    WPG: {
        abbreviation: "WPG",
        teamName: "Winnipeg Jets",
        id: "winnipeg-jets",
        conference: "West",
        division: "Central",
        league: "NHL",
        color: "#041E42"
    }
};

export const nhlStreams: SportStream[] = [
    {
        provider: "embedsports-top",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const homeId = nhlTeamsMap[homeTeamAbbrev as keyof typeof nhlTeamsMap]?.id;
            const awayId = nhlTeamsMap[awayTeamAbbrev as keyof typeof nhlTeamsMap]?.id;
            return `https://embedsports.top/embed/admin/ppv-${awayId}-vs-${homeId}/1`;
        },
    },
    {
        provider: "embedsports-home",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const id = nhlTeamsMap[homeTeamAbbrev as keyof typeof nhlTeamsMap].id;
            return `https://embedsports.me/nhl/${id}-stream-1`
        },
        label: "Home"
    },
    {
        provider: "embedsports-away",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const id = nhlTeamsMap[awayTeamAbbrev as keyof typeof nhlTeamsMap].id;
            return `https://embedsports.me/nhl/${id}-stream-1`
        },
        label: "Away"
    },

    {
        provider: "embedsports-d",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const homeId = nhlTeamsMap[homeTeamAbbrev as keyof typeof nhlTeamsMap]?.id;
            const awayId = nhlTeamsMap[awayTeamAbbrev as keyof typeof nhlTeamsMap]?.id;
            // return `https://embedsports.top/embed/admin/ppv-${awayId}-vs-${homeId}/1`;
            return `https://embedsports.me/nhl/${homeId}-vs-${awayId}-stream-1`;
        },
    },
    // ...createViewEmbedStreams(nhlTeamsMap),
]