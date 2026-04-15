import { Container } from "../../components/layout/Container/Container";
import "./Sports.css";
import { useSports } from "../../context/SportsContext";
import { AppSwiper } from "../../components/ui/AppSwiper/AppSwiper";
import { SwiperSkeletonCard } from "../../components/ui/MediaCard/SkeletonCards/MediaSkeletonCard";
import { channelStreams } from "../../data/sports/sportsData";
import { ChannelCard } from "../../components/ui/ChannelCard/ChannelCard";
import SportsLayout from "./SportsLayout";
import { FilteredSportsContainer } from "../../components/layout/Container/FilteredSportsContainer";
import RegularGameCard from "../../components/sports/GameCard/RegularGameCard";
import { SportCardsViewFactory } from "../../components/sports/SportCardsViews/SportCardsViewFactory";

const Sports = () => {
    const {
        nbaGamesLoading,
        nhlGamesLoading,
        mlbGamesLoading,
        nbaGameCards,
        nhlGameCards,
        mlbGameCards,
        favoriteGameCards,
        layout
    } = useSports();

    return (
        <SportsLayout title="Sports" subTitle="Browse live sports" league="all" >
            {/* {favoriteGameCards.length > 0 && (
                <FilteredSportsContainer title="Followed Teams">
                    <AppSwiper
                        items={favoriteGameCards}
                        itemKey={(item) => String(item.id ?? item.title)}
                        renderItem={(game) => (
                            <RegularGameCard game={game} />
                        )}
                        skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                    />
                </FilteredSportsContainer>
            )} */}
            <SportCardsViewFactory 
                games={favoriteGameCards}
                gamesLoading={false}
                title="Followed Teams"
                type="FOLLOW"
            />
            <FilteredSportsContainer type="TV" title="Sports Channels">
                <AppSwiper
                    items={channelStreams}
                    itemKey={(item) => item.title}
                    renderItem={(stream) => (
                        <ChannelCard stream={stream} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredSportsContainer>

            {/* <FilteredSportsContainer league="NBA" title="NBA">
                <AppSwiper
                    isLoading={nbaGamesLoading}
                    items={nbaGameCards}
                    itemKey={(item) => String(item.id ?? item.title)}
                    renderItem={(game) => (
                        <RegularGameCard game={game} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredSportsContainer> */}
            <SportCardsViewFactory 
                games={nbaGameCards}
                gamesLoading={nbaGamesLoading}
                title="NBA"
                type="NBA"
            />
            {/* <FilteredSportsContainer league="NHL" title="NHL">
                <AppSwiper
                    isLoading={nhlGamesLoading}
                    items={nhlGameCards}
                    itemKey={(item) => String(item.id ?? item.title)}
                    renderItem={(game) => (
                        <RegularGameCard game={game} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredSportsContainer> */}
            <SportCardsViewFactory 
                games={nhlGameCards}
                gamesLoading={nhlGamesLoading}
                title="NHL"
                type="NHL"
            />
            {/* <FilteredSportsContainer league="MLB" title="MLB">
                <AppSwiper
                    isLoading={mlbGamesLoading}
                    items={mlbGameCards}
                    itemKey={(item) => String(item.id ?? item.title)}
                    renderItem={(game) => (
                        <RegularGameCard game={game} />
                    )}
                    skeleton={<SwiperSkeletonCard className="game-card-skeleton" />}
                />
            </FilteredSportsContainer> */}
            <SportCardsViewFactory 
                games={mlbGameCards}
                gamesLoading={mlbGamesLoading}
                title="MLB"
                type="MLB"
            />
        </SportsLayout>

    );
};

export default Sports;