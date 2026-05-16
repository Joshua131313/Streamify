import { Swiper, SwiperSlide } from "swiper/react";
import { Navigation } from "swiper/modules";
import { useRef } from "react";
import { FaChevronLeft, FaChevronRight } from "react-icons/fa";
export type TSwiperVariant = "normal" | "top10"
import "./AppSwiper.css"

interface AppSwiperProps<T> {
    items: T[];
    renderItem: (item: T, index: number) => React.ReactNode;
    itemKey: (item: T) => string;
    isLoading?: boolean;
    skeleton?: React.ReactNode;
    variant?: TSwiperVariant;
}

export const AppSwiper = <T,>({
    items,
    renderItem,
    itemKey,
    isLoading,
    skeleton,
    variant = "normal",
}: AppSwiperProps<T>) => {
    const prevRef = useRef<HTMLDivElement | null>(null);
    const nextRef = useRef<HTMLDivElement | null>(null);
    const shouldShowSkeletons =
        isLoading && items.length === 0;
    return (
        <div className="swiper-container">
            {/* <div ref={prevRef} className="prev-button swiper-nav-button">
                <FaChevronLeft />
            </div>
            <div ref={nextRef} className="next-button swiper-nav-button">
                <FaChevronRight />
            </div> */}
            <div className="swiper-controls">
                <div ref={prevRef}><FaChevronLeft /></div>
                <div ref={nextRef}><FaChevronRight /></div>
            </div>
            <Swiper
                key={isLoading ? "loading" : "loaded"}
                className={`media-swiper ${variant === "top10" ? "top-10-media-swiper" : ""}`}
                slidesPerView={"auto"}
                spaceBetween={10}
                navigation
                modules={[Navigation]}
                onBeforeInit={(swiper) => {
                    //@ts-ignore
                    swiper.params.navigation.prevEl = prevRef.current;
                    //@ts-ignore
                    swiper.params.navigation.nextEl = nextRef.current;
                }}
            >
                {shouldShowSkeletons
                    ? Array.from({ length: 5 }).map((_, i) => (
                        <SwiperSlide key={`skeleton-${i}`}>{skeleton}</SwiperSlide>
                    ))
                    : items.map((item, i) => (
                        <SwiperSlide key={itemKey(item)}>
                            {renderItem(item, i)}
                        </SwiperSlide>
                    ))}
            </Swiper>

        </div>
    );
};