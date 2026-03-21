import { useState } from "react";
import { Container } from "../../components/layout/Container/Container"
import GameCard from "../../components/ui/GameCard/GameCard";
import { PageHeader } from "../../components/ui/PageHeader/PageHeader";
import { Title } from "../../components/ui/Title/Title"
import { useGames } from "../../hooks/sportsHooks/useGames"
import { AppPlayer } from "../../components/ui/AppPlayer/AppPlayer";
import "./Sports.css"
import { Input } from "../../components/ui/Input/Input";
import { FaSearch } from "react-icons/fa";
import { filterGames } from "../../utils/sports";

const Sports = () => {
    const { games, error, search, setSearch } = useGames();
    const [playerSrc, setPlayerSrc] = useState("");

    return (
        <div className="sports-page">
            <PageHeader
                title="Browse Sports"
                subTitle="Explore all live sports games"
                controls={
                <>
                    <Input 
                        placeholder="Search sports..."
                        Icon={FaSearch}
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                    />
                </>}
            />
            <Container title="NBA" className="sports-grid">
                {filterGames(games, search).map((game, index) => (
                    <GameCard showTag={false} key={index} game={game} setPlayerSrc={setPlayerSrc}/>
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