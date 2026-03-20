import { useState } from "react";
import { Container } from "../../components/layout/Container/Container"
import GameCard from "../../components/ui/GameCard/GameCard";
import { PageHeader } from "../../components/ui/PageHeader/PageHeader";
import { Title } from "../../components/ui/Title/Title"
import { useGames } from "../../hooks/sportsHooks/useGames"
import { AppPlayer } from "../../components/ui/AppPlayer/AppPlayer";
import "./Sports.css"

const Sports = () => {
    const { games, error } = useGames();
    const [playerSrc, setPlayerSrc] = useState("");

    return (
        <div className="sports-page">
            <PageHeader
                title="Browse Sports"
                subTitle="Explore all live sports games"
                controls={<></>}
            />
            <Container title="NBA" className="sports-grid">
                {games.map((game, index) => (
                    <GameCard key={index} game={game} setPlayerSrc={setPlayerSrc}/>
                ))}
            </Container>
            {
                playerSrc &&
                <AppPlayer
                    cancelPlay={() => setPlayerSrc("")}
                    src={playerSrc}

                />
            }
        </div>
    )
}
export default Sports;