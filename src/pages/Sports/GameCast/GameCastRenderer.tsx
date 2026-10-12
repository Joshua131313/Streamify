import { MLBLivePanel } from "../../../components/sports/GameCast/Panels/MLBLivePanel";
import { NBALivePanel } from "../../../components/sports/GameCast/Panels/NBALivePanel";
import { NHLLivePanel } from "../../../components/sports/GameCast/Panels/NHLLivePanel";
import type {
    SportDisplayGame
} from "../../../types/sports/sportsDisplayTypes";


interface Props {
    game: SportDisplayGame;
}

export const GameCastRenderer = ({
    game
}: Props) => {

    switch (game.league) {

        case "MLB":
            return (
                <MLBLivePanel
                    game={game}
                />
            );

        case "NBA":
        case "WNBA":
            return (
                <NBALivePanel
                    game={game}
                />
            );

        case "NHL":
            return (
                <NHLLivePanel
                    game={game}
                />
            );

        default:
            return null;
    }
};