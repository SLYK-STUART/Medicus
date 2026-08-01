-- Step 3: enable Realtime on hospitals + departments for live list streams.
ALTER PUBLICATION supabase_realtime ADD TABLE public.hospitals;
ALTER PUBLICATION supabase_realtime ADD TABLE public.departments;
