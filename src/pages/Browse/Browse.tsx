import { useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";

import { Container } from "../../components/layout/Container/Container";
import { StyledSelect } from "../../components/ui/StyledSelect/StyledSelect";

import type { TLabelValue, TMediaType } from "../../types/tmdb";

import { useInfiniteMediaBrowse } from "../../hooks/mediaHooks/useInfiniteMediaBrowse";
import { useInfiniteScroll } from "../../hooks/utilHooks/useInfiniteScroll";

import { MediaCard } from "../../components/ui/MediaCard/MediaCard";
import { MovieSeriesContainer } from "../../components/layout/Container/MovieSeriesContainer/MovieSeriesContainer";

import "./Browse.css";
import { PageHeader } from "../../components/ui/PageHeader/PageHeader";
import { getGenresByMedia } from "../../data/TMDBGenres";
import { GenreFilter } from "../../components/ui/filters/GenreFilter";
import { BrowseTypeFilter } from "../../components/ui/filters/BrowseTypeFilter";
import { Loader } from "../../components/ui/Loader/Loader";
import { SEO } from "../../components/SEO";

const Browse = () => {
  const [searchParams] = useSearchParams();

  const mediaType: TMediaType = searchParams.get("media") === "movie" ? "movie" : "tv";

  const browseType = searchParams.get("browseType")

  const loadMoreRef = useRef<HTMLDivElement | null>(null);

  const { media, genre, fetchNextPage, hasNextPage, isLoading } = useInfiniteMediaBrowse();

  useInfiniteScroll(loadMoreRef, fetchNextPage, !!hasNextPage);

  const isSeriesMode = mediaType === "movie" && browseType === "movie-series";

  return (
    <div className={`${mediaType === "movie" ? "movies-browse-page" : "shows-browse-page"} browse-page`}>
      {/* Header + Controls */}
      <SEO 
        title={`Browse ${mediaType === "tv" ? "Shows" : "Movies"}`}
        description="Browse movies and TV shows"
      />
      <PageHeader 
        title={mediaType === "tv" ? "Browse TV Shows" : "Browse Movies"}
        subTitle={`Explore thousands of ${mediaType === "movie" ? "movies" : "show"} in the catalog.`}
        controls={
          <>
          <GenreFilter mediaType={mediaType} includeAll/>
          {mediaType === "movie" && <BrowseTypeFilter />} 
          </>
        }
      />

      {/* Content */}
      {isLoading ?
       <Loader text="Media is loading..."/> :
        isSeriesMode ? (
          <MovieSeriesContainer genre={Number(genre?.value) || undefined} />
        ) : (
          <Container className="browse-results media-grid">
            {media.map((m) => (
              <MediaCard key={m.id} media={m} />
            ))}
          </Container>
        )
      }

      {/* Infinite scroll trigger */}
      <div ref={loadMoreRef} style={{ height: 1 }} />
    </div>
  );
};
export default Browse;