import type {
    SportDisplayGame
} from "../../../../types/sports/sportsDisplayTypes";

import { GameHeader } from "../GameHeader";
import { Scoreboard } from "../Scoreboard";
import { TeamStats } from "../TeamStats";

import { NHLLastPlay }
from "../../GameCard/nhl/components/NHLLastPlay";
import { NHLShotsDisplay } from "../../GameCard/nhl/components/NHLShotsDisplay";



interface Props {
    game: Extract<
        SportDisplayGame,
        { league: "NHL" }
    >;
}

export const NHLLivePanel = ({
    game
}: Props) => {

    const raw = game.raw;

    return (
        <>

            <GameHeader
                card={game.card}
            />

            <NHLShotsDisplay
                game={raw}
            />

            <NHLLastPlay
                game={raw}
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