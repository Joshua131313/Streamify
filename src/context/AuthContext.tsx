import { createContext, useContext, useEffect, useState } from "react";
import {
    signInWithPopup,
    GoogleAuthProvider,
    OAuthProvider,
    signInWithEmailAndPassword,
    createUserWithEmailAndPassword,
    signOut,
    onAuthStateChanged,
    sendPasswordResetEmail,
    updateProfile,
    getAdditionalUserInfo,
    FacebookAuthProvider,
    signInAnonymously,
} from "firebase/auth";
import { auth, db } from "../firebase/firebase";
import { createUserDocument } from "../firebase/auth";
import { useNavigate } from "react-router-dom";
import { Loader } from "../components/ui/Loader/Loader";
import { doc, FieldValue, getDoc, serverTimestamp, Timestamp } from "firebase/firestore";

type User = {
    email?: string | null;
    name?: string | null;
    image?: string | null;
    uid?: string;
} | null;

export type UserData = {
    createdAt: FieldValue;
    email: string;
    favoriteGenres: string[];
    firstName: string;
    lastName: string;
    onboardingComplete: boolean;
    updatedAt: FieldValue;
    userId: string;
}
const emptyUserData = {
    createdAt: serverTimestamp(),
    email: "",
    favoriteGenres: [],
    firstName: "",
    lastName: "",
    onboardingComplete: true,
    updatedAt: serverTimestamp(),
    userId: ""
}
export type ProviderType = "google" | "facebook";

interface AuthContextType {
    user: User;
    loading: boolean;
    userData: UserData;
    loginWithProvider: (provider: ProviderType) => Promise<void>;
    loginWithEmail: (email: string, password: string) => Promise<void>;

    register: (
        firstName: string,
        lastName: string,
        email: string,
        password: string
    ) => Promise<void>;

    logout: () => Promise<void>;
    resetPassword: (email: string) => Promise<void>;
}

const AuthContext = createContext<AuthContextType | null>(null);

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
    const [user, setUser] = useState<User>(null);
    const [userData, setUserData] = useState<UserData>(emptyUserData);
    const [loading, setLoading] = useState(true);
    const navigate = useNavigate();
    const [showLoader, setShowLoader] = useState(true);
    const [isExiting, setIsExiting] = useState(false);


    const loginWithProvider = async (providerType: ProviderType) => {
        let provider;

        if (providerType === "google") {
            provider = new GoogleAuthProvider();
        } else {
            provider = new FacebookAuthProvider();
        }

        const result = await signInWithPopup(auth, provider);

        const firebaseUser = result.user;

        const additionalInfo = getAdditionalUserInfo(result);
        const isNewUser = additionalInfo?.isNewUser;

        let name = firebaseUser.displayName;

        if (!name) {
            if (providerType === "facebook") {
                const profile = additionalInfo?.profile as {
                    name?: string;
                    first_name?: string;
                    last_name?: string;
                } | null;

                name =
                    profile?.name ||
                    `${profile?.first_name ?? ""} ${profile?.last_name ?? ""}`.trim() ||
                    "Facebook User";

            } else {
                name = "User";
            }
        }

        if (!firebaseUser.displayName && name) {
            await updateProfile(firebaseUser, { displayName: name });
        }

        if (isNewUser) {
            await createUserDocument(
                firebaseUser.uid,
                firebaseUser.email,
                undefined,
                undefined,
                name || ""
            );
            navigate("/customization")
        }
    };

    const loginWithEmail = async (email: string, password: string) => {
        await signInWithEmailAndPassword(auth, email, password);
    };

    const register = async (
        firstName: string,
        lastName: string,
        email: string,
        password: string
    ) => {
        const result = await createUserWithEmailAndPassword(auth, email, password);

        await updateProfile(result.user, {
            displayName: `${firstName} ${lastName}`,
        });

        await createUserDocument(
            result.user.uid,
            result.user.email,
            firstName,
            lastName
        );
        navigate("/customization")
    };

    const logout = async () => {
        await signOut(auth);
    };

    const resetPassword = async (email: string) => {
        await sendPasswordResetEmail(auth, email);
    };

    useEffect(() => {
        const unsubscribe = onAuthStateChanged(auth, (firebaseUser) => {
            if (firebaseUser) {
                setUser({
                    email: firebaseUser.email,
                    name: firebaseUser.displayName,
                    image: firebaseUser.photoURL,
                    uid: firebaseUser.uid,
                });
            } else {
                setUser(null);
            }
            setLoading(false);
        });

        return unsubscribe;
    }, []);

    useEffect(() => {
        const unsubscribe = onAuthStateChanged(auth, async (firebaseUser) => {
            if (!firebaseUser) {
                await signInAnonymously(auth);
                return;
            }
            if (firebaseUser) {
                setUser({
                    email: firebaseUser.email,
                    name: firebaseUser.displayName,
                    image: firebaseUser.photoURL,
                    uid: firebaseUser.uid,
                });

                const userRef = doc(db, "users", firebaseUser.uid);
                const snap = await getDoc(userRef);

                if (snap.exists()) {
                    setUserData(snap.data() as UserData);
                }
            } else {
                setUser(null);
                setUserData(emptyUserData);
            }

            setLoading(false);
        });

        return unsubscribe;
    }, []);

    useEffect(() => {
        if (!loading) {
            setIsExiting(true);
        }
    }, [loading]);

    return (
        <AuthContext.Provider
            value={{
                user,
                userData,
                loading,
                loginWithProvider,
                loginWithEmail,
                register,
                logout,
                resetPassword,
            }}
        >
            {showLoader && (
                <Loader
                    fullScreen
                    isExiting={isExiting}
                    onExitAnimationEnd={() => {
                        setShowLoader(false);
                    }}
                />
            )}
            {children}
        </AuthContext.Provider>
    );
};

export const useAuthProvider = () => {
    const ctx = useContext(AuthContext);
    if (!ctx) throw new Error("Auth must be used inside AuthProvider");
    return ctx;
};