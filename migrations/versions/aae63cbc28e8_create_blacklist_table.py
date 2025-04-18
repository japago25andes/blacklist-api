"""create blacklist table

Revision ID: aae63cbc28e8
Revises: 
Create Date: 2025-03-27 21:27:10.258656

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'aae63cbc28e8'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    op.create_table('blacklisted_emails',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('email', sa.String(length=255), nullable=False),
    sa.Column('app_uuid', sa.String(length=36), nullable=False),
    sa.Column('blocked_reason', sa.String(length=255), nullable=True),
    sa.Column('ip_address', sa.String(length=45), nullable=False),
    sa.Column('created_at', sa.DateTime(), nullable=True),
    sa.PrimaryKeyConstraint('id')
    )
    # ### end Alembic commands ###


def downgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    op.drop_table('blacklisted_emails')
    # ### end Alembic commands ###
