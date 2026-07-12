import asyncio
from sqlalchemy.ext.asyncio import create_async_engine

async def try_conn(uri, name):
    print(f"Testing {name}...")
    try:
        engine = create_async_engine(uri, connect_args={"timeout": 5})
        async with engine.connect() as conn:
            result = await conn.execute("SELECT 1")
            val = result.scalar()
            print(f"SUCCESS {name}! Select 1: {val}")
            return True
    except Exception as e:
        print(f"FAILED {name}: {e}")
        return False

async def main():
    options = [
        ("postgresql+asyncpg://postgres.knynttctxndoslqbajyp:civicvoice%4012@aws-0-ap-south-1.pooler.supabase.com:6543/postgres", "Pooler 6543 with tenant user"),
        ("postgresql+asyncpg://postgres.knynttctxndoslqbajyp:civicvoice%4012@aws-0-ap-south-1.pooler.supabase.com:5432/postgres", "Pooler 5432 with tenant user"),
        ("postgresql+asyncpg://postgres:civicvoice%4012@aws-0-ap-south-1.pooler.supabase.com:6543/postgres", "Pooler 6543 with simple postgres user"),
        ("postgresql+asyncpg://postgres:civicvoice%4012@aws-0-ap-south-1.pooler.supabase.com:5432/postgres", "Pooler 5432 with simple postgres user"),
    ]
    for uri, name in options:
        if await try_conn(uri, name):
            print(f"\nFOUND WORKING CONNECTION STRING:\n{uri}\n")
            break

if __name__ == "__main__":
    asyncio.run(main())
