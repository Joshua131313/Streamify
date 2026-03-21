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
import { filterGames, getStreamURL } from "../../utils/sports";
import { useSearchParams } from "react-router-dom";
import type { TStreamProvider } from "../../types/sports";

const Sports = () => {
    const { games, error, search, setSearch } = useGames();
    const [searchParams, setSearchParams] = useSearchParams();
    const provider = searchParams.get("provider");
    const channel = Number(searchParams.get("channel"));

    const cancelWatch = () => {
        searchParams.delete("provider");
        searchParams.delete("channel");
        setSearchParams(searchParams, {replace: true});
    }

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
                    <GameCard showTag={false} key={index} game={game} />
                ))}
            </Container>
            {
                channel && provider &&
                <AppPlayer
                    cancelPlay={cancelWatch}
                    src={getStreamURL(provider as TStreamProvider, channel)}
                />
            }
        </div>
    )
}
export default Sports;