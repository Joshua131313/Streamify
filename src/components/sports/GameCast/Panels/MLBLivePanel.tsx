import type {
    SportDisplayGame
} from "../../../../types/sports/sportsDisplayTypes";

import { GameHeader } from "../GameHeader";
import { Scoreboard } from "../Scoreboard";
import { PlayByPlay } from "../PlayByPlay";
import { TeamStats } from "../TeamStats";

import { MLBGameCardLiveInfo }
from "../../GameCard/mlb/components/MLBGameCardLiveInfo";

interface Props {
    game: Extract<
        SportDisplayGame,
        { league: "MLB" }
    >;
}

export const MLBLivePanel = ({
    game
}: Props) => {

    const raw = game.raw;

    return (
        <>

            <GameHeader
                card={game.card}
            />

            {raw.live && (
                <MLBGameCardLiveInfo
                    game={raw}
                    card={game.card}
                />
            )}

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