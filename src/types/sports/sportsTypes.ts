export type TStreamProvider = "trendy47" | "embedsports";
export type GameStatus = "LIVE" | "PRE" | "FUT" | "FINAL" | "HALFTIME";

export interface GameTeam {
    name: string;
    logo: string;
    score?: number;
}

export interface GameProps {
    id?: string | number;
    title: string;

    homeTeam: GameTeam;
    awayTeam: GameTeam;

    startTime: string;
    status: GameStatus;

    period?: string;
    periodNumber?: string;
    clock?: string;
    gameLink: string;
    sportName: "Basketball" | "Hockey";
    streamProvider: TStreamProvider;
    channel: string;
}
