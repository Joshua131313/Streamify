import { useParams } from "react-router-dom";
import { useEffect, useState } from "react";

import { Container } from "../../../components/layout/Container/Container";

import { useSports } from "../../../context/SportsContext";

import type {
    SportDisplayGame
} from "../../../types/sports/sportsDisplayTypes";

import type {
    Leagues
} from "../../../types/sports/sportsTypes";
import { GameCastRenderer } from "./GameCastRenderer";


const GameCast = () => {

    const {
        league,
        gameId
    } = useParams();

    const {
        getGame
    } = useSports();

    const [
        game,
        setGame
    ] = useState<
        SportDisplayGame | undefined
    >();

    const [
        loading,
        setLoading
    ] = useState(true);

    useEffect(() => {

        setLoading(true);

        const foundGame =
            getGame(
                league as Leagues,
                String(gameId)
            );
        setGame(foundGame);

        setLoading(false);

    }, [
        league,
        gameId,
        getGame
    ]);
console.log(game)
    if (loading) {
        return (
            <Container className="game-cast">
                Loading...
            </Container>
        );
    }

    if (!game) {
        return (
            <Container className="game-cast">
                Game not found.
            </Container>
        );
    }

    return (
        <Container className="game-cast">

            <GameCastRenderer
                game={game}
            />

        </Container>
    );
};

export default GameCast;