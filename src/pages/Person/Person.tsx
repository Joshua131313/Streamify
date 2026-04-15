import { useParams } from "react-router-dom";
import { usePerson } from "../../hooks/mediaHooks/personHooks/usePerson";
import { usePersonCredits } from "../../hooks/mediaHooks/personHooks/userPersonCredits";
import { Container } from "../../components/layout/Container/Container";
import { Loader } from "../../components/ui/Loader/Loader";
import { TMDBImg } from "../../components/ui/ImgProxy/TMDBImg";
import { MediaCard } from "../../components/ui/MediaCard/MediaCard";
import "./Person.css"
import { SEO } from "../../components/SEO";

const IMG = "https://image.tmdb.org/t/p/w500";

const PersonPage = () => {
    const { id } = useParams();

    const { data: person, isLoading } = usePerson(id!);
    const { media } = usePersonCredits(id!);

    if (isLoading || !person) return <Loader fullScreen />

    return (
        <Container className="person-page">
            <SEO
                title={person.name}
                description={person.biography}
            />
            <Container styled className="person-header">
                <TMDBImg
                    alt={person.name}
                    path={person.profile_path}
                    type="profile"
                    size="h632"
                />

                <div className="person-details">
                    <h1>{person.name}</h1>

                    {person.birthday && (
                        <p>
                            <strong>Birthday:</strong> {person.birthday}
                        </p>
                    )}

                    {person.place_of_birth && (
                        <p>
                            <strong>Place of Birth:</strong> {person.place_of_birth}
                        </p>
                    )}

                    {person.biography && (
                        <p className="person-bio">{person.biography}</p>
                    )}
                </div>

            </Container>
            <Container title="Known for" className="person-media-grid media-grid">
                {media.map((m) => (
                    <MediaCard key={m.id} media={m} />
                ))}
            </Container>

        </Container>
    );
};
export default PersonPage