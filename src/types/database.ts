export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type ClientType = "gym" | "individual";
export type ClassType = "group" | "private" | "supervising";
export type AttendanceStatus = "checked_in" | "late" | "missed" | "excused";

type Relationship = {
  columns: string[];
  foreignKeyName: string;
  isOneToOne?: boolean;
  referencedColumns: string[];
  referencedRelation: string;
};

type TableDefinition<Row, Insert, Update> = {
  Insert: Insert;
  Relationships: Relationship[];
  Row: Row;
  Update: Update;
};

export interface Database {
  public: {
    CompositeTypes: {};
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
        }
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
        }
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
        }
      >;
      clients: TableDefinition<
        {
          client_code: string;
          created_at: string;
          gym_id: string | null;
          id: string;
          name: string;
          type: ClientType;
        },
        {
          client_code?: string | null;
          created_at?: string;
          gym_id?: string | null;
          id?: string;
          name: string;
          type: ClientType;
        },
        {
          client_code?: string | null;
          created_at?: string;
          gym_id?: string | null;
          id?: string;
          name?: string;
          type?: ClientType;
        }
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
        }
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
        }
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
        }
      >;
    };
    Views: {};
  };
}

