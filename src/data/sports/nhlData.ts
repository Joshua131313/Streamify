import type { SportStream, TeamInfo } from "../../types/sports/sportsTypes";
import { createViewEmbedStreams } from "./sportsData";


export const nhlTeamsMap: Record<string, TeamInfo> = {
    ANA: { abbreviation: "ANA", teamName: "Anaheim Ducks", id: "anaheim-ducks", conference: "West", division: "Pacific", league: "NHL" },
    UTA: { abbreviation: "UTA", teamName: "Utah Mammoth", id: "utah-mammoth", conference: "West", division: "Central", league: "NHL" },
    BOS: { abbreviation: "BOS", teamName: "Boston Bruins", id: "boston-bruins", conference: "East", division: "Atlantic", league: "NHL" },
    BUF: { abbreviation: "BUF", teamName: "Buffalo Sabres", id: "buffalo-sabres", conference: "East", division: "Atlantic", league: "NHL" },
    CGY: { abbreviation: "CGY", teamName: "Calgary Flames", id: "calgary-flames", conference: "West", division: "Pacific", league: "NHL" },
    CAR: { abbreviation: "CAR", teamName: "Carolina Hurricanes", id: "carolina-hurricanes", conference: "East", division: "Metropolitan", league: "NHL" },
    CHI: { abbreviation: "CHI", teamName: "Chicago Blackhawks", id: "chicago-blackhawks", conference: "West", division: "Central", league: "NHL" },
    COL: { abbreviation: "COL", teamName: "Colorado Avalanche", id: "colorado-avalanche", conference: "West", division: "Central", league: "NHL" },
    CBJ: { abbreviation: "CBJ", teamName: "Columbus Blue Jackets", id: "columbus-blue-jackets", conference: "East", division: "Metropolitan", league: "NHL" },
    DAL: { abbreviation: "DAL", teamName: "Dallas Stars", id: "dallas-stars", conference: "West", division: "Central", league: "NHL" },
    DET: { abbreviation: "DET", teamName: "Detroit Red Wings", id: "detroit-red-wings", conference: "East", division: "Atlantic", league: "NHL" },
    EDM: { abbreviation: "EDM", teamName: "Edmonton Oilers", id: "edmonton-oilers", conference: "West", division: "Pacific", league: "NHL" },
    FLA: { abbreviation: "FLA", teamName: "Florida Panthers", id: "florida-panthers", conference: "East", division: "Atlantic", league: "NHL" },
    LA: { abbreviation: "LA", teamName: "Los Angeles Kings", id: "los-angeles-kings", conference: "West", division: "Pacific", league: "NHL" },
    MIN: { abbreviation: "MIN", teamName: "Minnesota Wild", id: "minnesota-wild", conference: "West", division: "Central", league: "NHL" },
    MTL: { abbreviation: "MTL", teamName: "Montreal Canadiens", id: "montreal-canadiens", conference: "East", division: "Atlantic", league: "NHL" },
    NSH: { abbreviation: "NSH", teamName: "Nashville Predators", id: "nashville-predators", conference: "West", division: "Central", league: "NHL" },
    NJ: { abbreviation: "NJ", teamName: "New Jersey Devils", id: "new-jersey-devils", conference: "East", division: "Metropolitan", league: "NHL" },
    NYI: { abbreviation: "NYI", teamName: "New York Islanders", id: "new-york-islanders", conference: "East", division: "Metropolitan", league: "NHL" },
    NYR: { abbreviation: "NYR", teamName: "New York Rangers", id: "new-york-rangers", conference: "East", division: "Metropolitan", league: "NHL" },
    OTT: { abbreviation: "OTT", teamName: "Ottawa Senators", id: "ottawa-senators", conference: "East", division: "Atlantic", league: "NHL" },
    PHI: { abbreviation: "PHI", teamName: "Philadelphia Flyers", id: "philadelphia-flyers", conference: "East", division: "Metropolitan", league: "NHL" },
    PIT: { abbreviation: "PIT", teamName: "Pittsburgh Penguins", id: "pittsburgh-penguins", conference: "East", division: "Metropolitan", league: "NHL" },
    SJ: { abbreviation: "SJ", teamName: "San Jose Sharks", id: "san-jose-sharks", conference: "West", division: "Pacific", league: "NHL" },
    SEA: { abbreviation: "SEA", teamName: "Seattle Kraken", id: "seattle-kraken", conference: "West", division: "Pacific", league: "NHL" },
    STL: { abbreviation: "STL", teamName: "St. Louis Blues", id: "st-louis-blues", conference: "West", division: "Central", league: "NHL" },
    TB: { abbreviation: "TB", teamName: "Tampa Bay Lightning", id: "tampa-bay-lightning", conference: "East", division: "Atlantic", league: "NHL" },
    TOR: { abbreviation: "TOR", teamName: "Toronto Maple Leafs", id: "toronto-maple-leafs", conference: "East", division: "Atlantic", league: "NHL" },
    VAN: { abbreviation: "VAN", teamName: "Vancouver Canucks", id: "vancouver-canucks", conference: "West", division: "Pacific", league: "NHL" },
    VGK: { abbreviation: "VGK", teamName: "Vegas Golden Knights", id: "vegas-golden-knights", conference: "West", division: "Pacific", league: "NHL" },
    WSH: { abbreviation: "WSH", teamName: "Washington Capitals", id: "washington-capitals", conference: "East", division: "Metropolitan", league: "NHL" },
    WPG: { abbreviation: "WPG", teamName: "Winnipeg Jets", id: "winnipeg-jets", conference: "West", division: "Central", league: "NHL" }
};


export const nhlStreams: SportStream[] = [
    {
        provider: "embedsports",
        buildStreamUrl: ({awayTeamAbbrev, homeTeamAbbrev}) => {
            const homeId = nhlTeamsMap[homeTeamAbbrev as keyof typeof nhlTeamsMap]?.id;
            const awayId = nhlTeamsMap[awayTeamAbbrev as keyof typeof nhlTeamsMap]?.id;
            return `https://embedsports.top/embed/admin/ppv-${awayId}-vs-${homeId}/1`;
        },
    },
    {
        provider: "embedsports-d",
        buildStreamUrl: ({awayTeamAbbrev, homeTeamAbbrev}) => {
            const homeId = nhlTeamsMap[homeTeamAbbrev as keyof typeof nhlTeamsMap]?.id;
            const awayId = nhlTeamsMap[awayTeamAbbrev as keyof typeof nhlTeamsMap]?.id;
            // return `https://embedsports.top/embed/admin/ppv-${awayId}-vs-${homeId}/1`;
            console.log(homeTeamAbbrev)
            return `https://embedsports.me/nhl/${homeId}-vs-${awayId}-stream-1`;
        },
    },
    ...createViewEmbedStreams(nhlTeamsMap),
]