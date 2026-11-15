export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type ClientType = "gym" | "individual";
export type ClientStatus = "pending" | "approved" | "rejected";
export type ClassType = "group" | "private" | "supervising";
export type AttendanceStatus = "checked_in" | "late" | "missed" | "excused";

type Relationship = {
  columns: string[];
  foreignKeyName: string;
  isOneToOne?: boolean;
  referencedColumns: string[];
  referencedRelation: string;
};

// NX-25: TableDefinition takes the table's foreign keys as a 4th type
// argument. It used to default Relationships to a bare Relationship[],
// so the generated type listed NO relations at all and supabase-js
// could not resolve ANY embedded select (every `client:clients(...)`
// / `coach:coaches(...)` embed typed as SelectQueryError, which is why
// the queries were full of `as any`). The relations below are taken
// from database/archive/schema.sql (constraint names included).
type TableDefinition<
  Row,
  Insert,
  Update,
  Rels extends Relationship[] = [],
> = {
  Insert: Insert;
  Relationships: Rels;
  Row: Row;
  Update: Update;
};

export interface Database {
  public: {
    CompositeTypes: Record<string, never>;
    Enums: {
      attendance_status: AttendanceStatus;
      class_type: ClassType;
      client_type: ClientType;
    };
    Functions: {
      provision_new_gym: {
        Args: {
          p_email: string;
          p_full_name?: string | null;
          p_gym_name: string;
          p_user_id: string;
        };
        Returns: {
          admin_role_id: string;
          gym_id: string;
        }[];
      };
    };
    Tables: {
      attendance: TableDefinition<
        {
          class_id: string | null;
          client_id: string;
          gym_id: string;
          id: string;
          status: AttendanceStatus;
          timestamp: string;
        },
        {
          class_id?: string | null;
          client_id: string;
          gym_id: string;
          id?: string;
          status?: AttendanceStatus;
          timestamp?: string;
        },
        {
          class_id?: string | null;
          client_id?: string;
          gym_id?: string;
          id?: string;
          status?: AttendanceStatus;
          timestamp?: string;
        },
        [
          {
            columns: ["class_id"];
            foreignKeyName: "attendance_class_id_fkey";
            referencedColumns: ["id"];
            referencedRelation: "classes";
          },
          {
            columns: ["client_id"];
            foreignKeyName: "attendance_client_id_fkey";
            referencedColumns: ["id"];
            referencedRelation: "clients";
          },
          {
            columns: ["gym_id"];
            foreignKeyName: "attendance_gym_id_fkey";
            referencedColumns: ["id"];
            referencedRelation: "gyms";
          },
        ]
      >;
      class_clients: TableDefinition<
        {
          class_id: string;
          client_id: string;
          id: string;
        },
        {
          class_id: string;
          client_id: string;
          id?: string;
        },
        {
          class_id?: string;
          client_id?: string;
          id?: string;
        },
        [
          {
            columns: ["class_id"];
            foreignKeyName: "class_clients_class_id_fkey";
            referencedColumns: ["id"];
            referencedRelation: "classes";
          },
          {
            columns: ["client_id"];
            foreignKeyName: "class_clients_client_id_fkey";
            referencedColumns: ["id"];
            referencedRelation: "clients";
          },
        ]
      >;
      classes: TableDefinition<
        {
          capacity: number | null;
          coach_id: string;
          created_at: string;
          gym_id: string;
          id: string;
          name: string;
          type: ClassType;
        },
        {
          capacity?: number | null;
          coach_id: string;
          created_at?: string;
          gym_id: string;
          id?: string;
          name: string;
          type: ClassType;
        },
        {
          capacity?: number | null;
          coach_id?: string;
          created_at?: string;
          gym_id?: string;
          id?: string;
          name?: string;
          type?: ClassType;
        },
        [
          {
            columns: ["coach_id", "gym_id"];
            foreignKeyName: "classes_coach_gym_fk";
            referencedColumns: ["id", "gym_id"];
            referencedRelation: "coaches";
          },
          {
            columns: ["gym_id"];
            foreignKeyName: "classes_gym_id_fkey";
            referencedColumns: ["id"];
            referencedRelation: "gyms";
          },
        ]
      >;
      clients: TableDefinition<
        {
          client_code: string;
          contact_verified: boolean;
          created_at: string;
          email: string | null;
          gym_id: string | null;
          id: string;
          name: string;
          phone: string | null;
          status: ClientStatus;
          type: ClientType;
        },
        {
          client_code?: string | null;
          contact_verified?: boolean;
          created_at?: string;
          email?: string | null;
          gym_id?: string | null;
          id?: string;
          name: string;
          phone?: string | null;
          status?: ClientStatus;
          type: ClientType;
        },
        {
          client_code?: string | null;
          contact_verified?: boolean;
          created_at?: string;
          email?: string | null;
          gym_id?: string | null;
          id?: string;
          name?: string;
          phone?: string | null;
          status?: ClientStatus;
          type?: ClientType;
        },
        [
          {
            columns: ["gym_id"];
            foreignKeyName: "clients_gym_id_fkey";
            referencedColumns: ["id"];
            referencedRelation: "gyms";
          },
        ]
      >;
      coaches: TableDefinition<
        {
          created_at: string;
          gym_id: string;
          id: string;
          name: string;
          rating: number | null;
        },
        {
          created_at?: string;
          gym_id: string;
          id?: string;
          name: string;
          rating?: number | null;
        },
        {
          created_at?: string;
          gym_id?: string;
          id?: string;
          name?: string;
          rating?: number | null;
        },
        [
          {
            columns: ["gym_id"];
            foreignKeyName: "coaches_gym_id_fkey";
            referencedColumns: ["id"];
            referencedRelation: "gyms";
          },
        ]
      >;
      gyms: TableDefinition<
        {
          created_at: string;
          id: string;
          name: string;
        },
        {
          created_at?: string;
          id?: string;
          name: string;
        },
        {
          created_at?: string;
          id?: string;
          name?: string;
        }
      >;
      roles: TableDefinition<
        {
          created_at: string;
          gym_id: string;
          id: string;
          name: string;
          permissions: Json;
        },
        {
          created_at?: string;
          gym_id: string;
          id?: string;
          name: string;
          permissions?: Json;
        },
        {
          created_at?: string;
          gym_id?: string;
          id?: string;
          name?: string;
          permissions?: Json;
        },
        [
          {
            columns: ["gym_id"];
            foreignKeyName: "roles_gym_id_fkey";
            referencedColumns: ["id"];
            referencedRelation: "gyms";
          },
        ]
      >;
      users: TableDefinition<
        {
          created_at: string;
          email: string;
          full_name: string | null;
          gym_id: string;
          id: string;
          role_id: string;
        },
        {
          created_at?: string;
          email: string;
          full_name?: string | null;
          gym_id: string;
          id: string;
          role_id: string;
        },
        {
          created_at?: string;
          email?: string;
          full_name?: string | null;
          gym_id?: string;
          id?: string;
          role_id?: string;
        },
        [
          {
            columns: ["gym_id"];
            foreignKeyName: "users_gym_id_fkey";
            referencedColumns: ["id"];
            referencedRelation: "gyms";
          },
          {
            columns: ["role_id", "gym_id"];
            foreignKeyName: "users_role_gym_fk";
            referencedColumns: ["id", "gym_id"];
            referencedRelation: "roles";
          },
        ]
      >;
    };
    Views: Record<string, never>;
  };
}

