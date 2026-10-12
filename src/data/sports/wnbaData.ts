import type { SportStream, TeamInfo } from "../../types/sports/sportsTypes";
import { getSlug } from "./sportsData";

export const wnbaTeamsMap: Record<string, TeamInfo> = {
    ATL: { abbreviation: "ATL", teamName: "Atlanta Dream", id: "atlanta-dream", conference: "East", division: "Eastern", league: "WNBA", color: "#E31837" },
    CHI: { abbreviation: "CHI", teamName: "Chicago Sky", id: "chicago-sky", conference: "East", division: "Eastern", league: "WNBA", color: "#5091CD" },
    CON: { abbreviation: "CON", teamName: "Connecticut Sun", id: "connecticut-sun", conference: "East", division: "Eastern", league: "WNBA", color: "#F05023" },
    DAL: { abbreviation: "DAL", teamName: "Dallas Wings", id: "dallas-wings", conference: "West", division: "Western", league: "WNBA", color: "#002B5C" },
    GS: { abbreviation: "GS", teamName: "Golden State Valkyries", id: "golden-state-valkyries", conference: "West", division: "Western", league: "WNBA", color: "#B38BC8" },
    IND: { abbreviation: "IND", teamName: "Indiana Fever", id: "indiana-fever", conference: "East", division: "Eastern", league: "WNBA", color: "#002D62" },
    LV: { abbreviation: "LV", teamName: "Las Vegas Aces", id: "las-vegas-aces", conference: "West", division: "Western", league: "WNBA", color: "#000000" },
    LA: { abbreviation: "LA", teamName: "Los Angeles Sparks", id: "los-angeles-sparks", conference: "West", division: "Western", league: "WNBA", color: "#552583" },
    MIN: { abbreviation: "MIN", teamName: "Minnesota Lynx", id: "minnesota-lynx", conference: "West", division: "Western", league: "WNBA", color: "#0C2340" },
    NY: { abbreviation: "NY", teamName: "New York Liberty", id: "new-york-liberty", conference: "East", division: "Eastern", league: "WNBA", color: "#86CEBC" },
    PHX: { abbreviation: "PHX", teamName: "Phoenix Mercury", id: "phoenix-mercury", conference: "West", division: "Western", league: "WNBA", color: "#201747" },
    POR: { abbreviation: "POR", teamName: "Portland Fire", id: "portland-fire", conference: "West", division: "Western", league: "WNBA", color: "#E03A3E" },
    SEA: { abbreviation: "SEA", teamName: "Seattle Storm", id: "seattle-storm", conference: "West", division: "Western", league: "WNBA", color: "#2C5234" },
    TOR: { abbreviation: "TOR", teamName: "Toronto Tempo", id: "toronto-tempo", conference: "East", division: "Eastern", league: "WNBA", color: "#7A143D" },
    WSH: { abbreviation: "WSH", teamName: "Washington Mystics", id: "washington-mystics", conference: "East", division: "Eastern", league: "WNBA", color: "#E03A3E" },
};

export const wnbaStreams: SportStream[] = [
    {
        provider: "embedsports-top",
        buildStreamUrl: ({ awayTeamAbbrev, homeTeamAbbrev }) => {
            const away = wnbaTeamsMap[awayTeamAbbrev as keyof typeof wnbaTeamsMap];
            const home = wnbaTeamsMap[homeTeamAbbrev as keyof typeof wnbaTeamsMap];

            if (!away || !home) return "";

            return `https://embedsports.top/embed/admin/ppv-${away.id}-vs-${home.id}/1`;
        },
    },
    // {
    //     provider: "sportspass",
    //     buildStreamUrl: ({ awayTeamAbbrev }) => {
    //         const team = wnbaTeamsMap[awayTeamAbbrev as keyof typeof wnbaTeamsMap];

    //         if (!team) return "";

    //         const slug = getSlug(team.teamName);
    //         return `https://sportspass.top/wnba/${slug}.html`;
    //     },
    // },
    {
        provider: "embedsports-home",
        buildStreamUrl: ({ homeTeamAbbrev }) => {
            const team = wnbaTeamsMap[homeTeamAbbrev as keyof typeof wnbaTeamsMap];

            if (!team) return "";

            return `https://embedsports.me/wnba/${team.id}-stream-1`;
        },
        label: "Home",
    },
    {
        provider: "embedsports-away",
        buildStreamUrl: ({ awayTeamAbbrev }) => {
            const team = wnbaTeamsMap[awayTeamAbbrev as keyof typeof wnbaTeamsMap];

            if (!team) return "";

            return `https://embedsports.me/wnba/${team.id}-stream-1`;
        },
        label: "Away",
    },
];