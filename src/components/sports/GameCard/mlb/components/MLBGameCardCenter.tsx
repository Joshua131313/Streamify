import {
    FaArrowDown,
    FaArrowUp,
} from "react-icons/fa";

import type {
    IMLBGame
} from "../../../../../types/sports/mlbTypes";

import {
    getOrdinalSuffix
} from "../../../../../utils/sports/sportsUtils";

import { MLBDiamond } from "./MLBDiamond";

interface Props {
    game: IMLBGame;
}

export const MLBGameCardCenter = ({
    game
}: Props) => {

    const isPregame =
        game.state === "pre";

    const isFinal =
        game.state === "post" ||
        game.completed;

    const isLive =
        !isPregame &&
        !isFinal;

    const inningHalf =
        game.period?.inningHalf
            ?.toLowerCase();

    const inningNumber =
        game.period?.current;

    const inningText =
        inningNumber
            ? `${inningNumber}${getOrdinalSuffix(inningNumber)}`
            : "—";

    const isTopInning =
        inningHalf === "top";

    const isBottomInning =
        inningHalf === "bottom";

    const inningStateText =
        inningHalf === "middle"
            ? "Mid"

            : inningHalf === "end"
                ? "End"

                : null;

    const balls =
        game.live?.balls ?? 0;

    const strikes =
        game.live?.strikes ?? 0;

    const outs =
        game.live?.outs ?? 0;

    const bases =
        game.live?.bases;

    return (
        <div className="sport-center-column">

            <div className="sport-inning-row">

                {isLive && isTopInning && (
                    <FaArrowUp />
                )}

                {isLive && isBottomInning && (
                    <FaArrowDown />
                )}

                {isLive &&
                    inningStateText && (
                        <span>
                            {inningStateText}
                        </span>
                    )}

                <span>
                    {isPregame
                        ? "Scheduled"

                        : isFinal
                            ? "Final"

                            : inningText}
                </span>

            </div>

            <div className="sport-count-row">

                {isPregame
                    ? game.venue ?? "MLB"

                    : isFinal
                        ? game.broadcasts?.[0] ?? "MLB"

                        : `${balls}-${strikes}`}

            </div>

            {isLive && (
                <MLBDiamond
                    bases={bases}
                    outs={outs}
                />
            )}

        </div>
    );
};