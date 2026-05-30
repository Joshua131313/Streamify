import { DateTime } from "luxon";

import type {
    INHLGame
} from "../../../../../types/sports/nhlTypes";

import {
    getOrdinalSuffix
} from "../../../../../utils/sports/sportsUtils";

interface Props {
    game: INHLGame;
}

export const NHLGameCardCenter = ({
    game
}: Props) => {

    const isPregame =
        game.state === "pre";

    const isFinal =
        game.state === "post";

    const currentPeriod =
        game.period?.current;

    const periodText =
        isPregame
            ? DateTime.fromISO(game.date)
                .toFormat("MMM d")

            : game.period.type === "SO"
                ? "Shootout"

                : game.period.type === "OT"
                    ? `OT ${currentPeriod}`

                    : isFinal
                        ? "Final"

                        : `${currentPeriod}${getOrdinalSuffix(currentPeriod)}`;

    return (
        <div className="sport-center-column">

            <div className="sport-inning-row">

                <span>
                    {periodText}
                </span>

            </div>

            <div className="sport-count-row">

                {isPregame
                    ? game.venue ?? "NHL"

                    : isFinal
                        ? game.broadcasts?.[0] ?? "NHL"

                        : game.clock}

            </div>

        </div>
    );
};