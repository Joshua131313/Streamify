import type {
    SportDisplayGame
} from "../../../../types/sports/sportsDisplayTypes";

import { GameHeader } from "../GameHeader";
import { Scoreboard } from "../Scoreboard";
import { PlayByPlay } from "../PlayByPlay";
import { TeamStats } from "../TeamStats";

interface Props {
    game: Extract<
        SportDisplayGame,
        {
            league: "NBA"
        } | {
            league: "WNBA"
        }
    >;
}

export const NBALivePanel = ({
    game
}: Props) => {

    const raw = game.raw;

    return (
        <>

            <GameHeader
                card={game.card}
            />

            <div
                className="gamecast-fouls"
                style={{
                    display: "flex",
                    justifyContent: "center",
                    gap: "1rem",
                    marginBottom: "1rem"
                }}
            >

                <span>
                    Away Fouls:
                    {raw.live?.awayFouls ?? "-"}
                </span>

                <span>
                    Home Fouls:
                    {raw.live?.homeFouls ?? "-"}
                </span>

                <span>
                    Away TO:
                    {raw.live?.awayTimeouts ?? "-"}
                </span>

                <span>
                    Home TO:
                    {raw.live?.homeTimeouts ?? "-"}
                </span>

            </div>

            <PlayByPlay
                game={game}
            />

            <Scoreboard
                game={game}
            />

            <TeamStats
                game={game}
            />

        </>
    );
};