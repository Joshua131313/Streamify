import type { GameProps } from "../../../types/sports/sportsTypes";
import { SidebarCard } from "./SidebarCard"
import { useGameCard } from "./useGameCard";
import "./GameCard.css"

interface Props {
    game: GameProps;
}

export const GameGroupCard = (props: Props) => {
    const { game } = props;
    const { getGameStatusUI } = useGameCard(game);

    return (
        <div className="game-group" key={game.id}>
            <div className="game-group-badges">
                <span className="status-tag">{getGameStatusUI("compact").statusDetail}</span>
            </div>
            <SidebarCard team={game.awayTeam} game={game} />
            <SidebarCard team={game.homeTeam} game={game} />
        </div>
    )
}