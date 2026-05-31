import type {
    INHLGame
} from "../../../../../types/sports/nhlTypes";

import type {
    GameProps
} from "../../../../../types/sports/sportsTypes";

import {
    PeriodGroup
} from "../../PeriodGroup";

interface Props {
    game: INHLGame;
    card: GameProps;
}

export const NHLLinescore = ({
    game,
    card
}: Props) => {

    const basePeriods =
        game.live?.periodScores?.length ?? 3;

    const extraPeriods =
        (game.period.type === "OT"
            ? 1
            : 0) +
        (game.period.type === "SO"
            ? 1
            : 0);

    const periodsPlayed =
        basePeriods +
        extraPeriods;

    return (
        <div className="sport-linescore">

            <div className="sport-linescore-header">

                <span className="team-cell" />

                <PeriodGroup
                    periodsPlayed={periodsPlayed}
                >

                    {game.live?.periodScores?.map(period => (
                        <span
                            key={period.period}
                            className="inning-cell"
                        >
                            {period.period}
                        </span>
                    ))}

                    {game.period.type === "OT" && (
                        <span className="inning-cell">
                            OT
                        </span>
                    )}

                    {game.period.type === "SO" && (
                        <span className="inning-cell">
                            SO
                        </span>
                    )}

                </PeriodGroup>

                <div className="nhl-totals-group">

                    <span className="total-cell">
                        G
                    </span>

                    <span className="total-cell">
                        S
                    </span>

                </div>

            </div>

            <div className="sport-linescore-row">

                <span className="team-cell">
                    {card.awayTeam.abbrev}
                </span>

                <PeriodGroup
                    periodsPlayed={periodsPlayed}
                >

                    {game.live?.periodScores?.map(period => (
                        <span
                            key={`away-${period.period}`}
                            className={`${Number(period.away) > Number(period.home)
                                ? "greater"
                                : ""
                                } inning-cell`}
                        >
                            {period.away ?? "-"}
                        </span>
                    ))}

                </PeriodGroup>

                <div className="nhl-totals-group">

                    <span className="total-cell">
                        {game.awayTeam.score}
                    </span>

                    <span className="total-cell">
                        {game.awayTeam.shots ?? "-"}
                    </span>

                </div>

            </div>

            <div className="sport-linescore-row">

                <span className="team-cell">
                    {card.homeTeam.abbrev}
                </span>

                <PeriodGroup
                    periodsPlayed={periodsPlayed}
                >

                    {game.live?.periodScores?.map(period => (
                        <span
                            key={`home-${period.period}`}
                            className={`${Number(period.home) > Number(period.away)
                                ? "greater"
                                : ""
                                } inning-cell`}
                        >
                            {period.home ?? "-"}
                        </span>
                    ))}

                </PeriodGroup>

                <div className="nhl-totals-group">

                    <span className="total-cell">
                        {game.homeTeam.score}
                    </span>

                    <span className="total-cell">
                        {game.homeTeam.shots ?? "-"}
                    </span>

                </div>

            </div>

        </div>
    );
};