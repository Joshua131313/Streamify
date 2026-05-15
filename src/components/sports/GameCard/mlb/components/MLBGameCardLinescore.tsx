import type {
    GameProps
} from "../../../../../types/sports/sportsTypes";

import type {
    IMLBGame
} from "../../../../../types/sports/mlbTypes";

import {
    PeriodGroup
} from "../../PeriodGroup";

interface Props {
    game: IMLBGame;

    card: GameProps;
}

export const MLBGameCardLinescore = ({
    game,
    card
}: Props) => {

    const inningsPlayed =
        game.live?.linescore?.length ?? 9;

    return (
        <div className="sport-linescore">

            <div className="sport-linescore-header">

                <span className="team-cell" />

                <PeriodGroup
                    periodsPlayed={inningsPlayed}
                >

                    {game.live?.linescore?.map(line => (
                        <span
                            key={line.inning}
                            className="inning-cell"
                        >
                            {line.inning}
                        </span>
                    ))}

                </PeriodGroup>

                <div className="totals-group">

                    <span className="total-cell">
                        R
                    </span>

                    <span className="total-cell">
                        H
                    </span>

                    <span className="total-cell">
                        E
                    </span>

                </div>

            </div>

            <div className="sport-linescore-row">

                <span className="team-cell">
                    {card.awayTeam.abbrev}
                </span>

                <PeriodGroup
                    periodsPlayed={inningsPlayed}
                >

                    {game.live?.linescore?.map(line => (
                        <span
                            key={`away-${line.inning}`}
                            className="inning-cell"
                        >
                            {line.away ?? "-"}
                        </span>
                    ))}

                </PeriodGroup>

                <div className="totals-group">

                    <span className="total-cell">
                        {game.awayTeam.score}
                    </span>

                    <span className="total-cell">
                        {game.awayTeam.hits ?? "-"}
                    </span>

                    <span className="total-cell">
                        {game.awayTeam.errors ?? "-"}
                    </span>

                </div>

            </div>

            <div className="sport-linescore-row">

                <span className="team-cell">
                    {card.homeTeam.abbrev}
                </span>

                <PeriodGroup
                    periodsPlayed={inningsPlayed}
                >

                    {game.live?.linescore?.map(line => (
                        <span
                            key={`home-${line.inning}`}
                            className="inning-cell"
                        >
                            {line.home ?? "-"}
                        </span>
                    ))}

                </PeriodGroup>

                <div className="totals-group">

                    <span className="total-cell">
                        {game.homeTeam.score}
                    </span>

                    <span className="total-cell">
                        {game.homeTeam.hits ?? "-"}
                    </span>

                    <span className="total-cell">
                        {game.homeTeam.errors ?? "-"}
                    </span>

                </div>

            </div>

        </div>
    );
};