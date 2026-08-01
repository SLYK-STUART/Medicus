-- Step 2: enable Realtime on profiles so watchUserProfile can subscribe.
ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
