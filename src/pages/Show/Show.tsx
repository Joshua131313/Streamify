import { useParams } from "react-router-dom";
import { useShow } from "../../hooks/mediaHooks/showHooks/useShow";
import { Trailer } from "../../components/ui/Trailer/Trailer";
import { MediaLayout } from "../../components/layout/MediaLayout/MediaLayout";
import { Container } from "../../components/layout/Container/Container";
import Select from "react-select";
import { useEffect, useState } from "react";
import type { TSeason } from "../../types/TMDBShowType";
import { Input } from "../../components/ui/Input/Input";
import { FaDirections, FaSearch, FaSort, FaSortAmountDownAlt, FaSortAmountUpAlt } from "react-icons/fa";
import "./Show.css"
import { Icon } from "../../components/ui/Icon/Icon";
import { StyledSelect } from "../../components/ui/StyledSelect/StyledSelect";
import { MediaLayoutProvider } from "../../components/layout/MediaLayout/MediaLayoutContext";
import { useEpisodes } from "../../hooks/mediaHooks/showHooks/useEpisodes";
import { Title } from "../../components/ui/Title/Title";
import { EpisodesControls } from "./EpisodesControls";
import { EpisodesList } from "./EpisodesList";
import { EpisodesProvider } from "./EpisodesProvider";


const Show = ()  => {
    const { showId } = useParams();
    const { show, isLoading, error } = useShow({showId: showId!});

    return (
        <MediaLayout media={show!} error={error} isLoading={isLoading} mediaType="tv">
            <EpisodesProvider show={show!}>
                <EpisodesControls />
                <EpisodesList />
            </EpisodesProvider>
        </MediaLayout>
    )
}
export default Show;