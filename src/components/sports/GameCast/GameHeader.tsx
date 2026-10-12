import { GameCardTeam } from "../GameCard/GameCardTeam";
import { useGameCard } from "../GameCard/useGameCard";

import type {
    GameProps
} from "../../../types/sports/sportsTypes";

interface Props {
    card: GameProps;
}

export const GameHeader = ({
    card
}: Props) => {

    const {
        leadingTeam
    } = useGameCard(card);

    return (
        <div className="gamecast-header">

            <GameCardTeam
                game={card}
                teamKey="awayTeam"
                leadingTeam={leadingTeam}
                showTeamName
                showFollowButton
            />

            <GameCardTeam
                game={card}
                teamKey="homeTeam"
                leadingTeam={leadingTeam}
                showTeamName
                showFollowButton
            />

        </div>
    );
};